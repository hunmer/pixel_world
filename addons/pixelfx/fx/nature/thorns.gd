# The wave (spikes punching up one after another, each bigger, with overshoot, a white frame, a burst of debris
# and glints, a line running along the floor ahead of them) is adapted from Sprite Fusion's open-source ice
# spikes (https://www.spritefusion.com/pixel-art-vfx/ice), MIT License, Copyright (c) 2026 Hugo Duprez.
# port-of: src/fx/nature/thorns.js@2966fdd134ae493a3760bf2f1fedd3f4674c8dd9
extends "../../core/effect.gd"

const Px := preload("../../core/px.gd")
const Lib := preload("_lib.gd")
const P := Px.P
const WHITE := Px.WHITE

static var meta := {
	"name": "Thorns",
	"desc": "A seam races along the floor and hooked thorns punch up out of it one after another, each bigger than the last, in bursts of dirt and green light; they hold, then sink.",
	"tags": ["nature", "thorns", "plant", "spikes", "ground", "attack", "one-shot"],
	"size": [232, 92],
	"origin": [48, 78],
	"duration": 2.4,
	"loop": false,
	"fps": 30,
	"bg": "ground",
	"options": {
		"palette": ["#160c0e", "#2e1418", "#4e2224", "#743a30", "#9a5a3e", "#c08458", "#e2b484", "#fbe8c8"],
		"glow": ["#123818", "#2f7a2a", "#6cb83a", "#c8f070"],
		"soil": ["#120c0c", "#251917", "#3b2a24", "#553d31", "#715440", "#8f6e52", "#b8966e", "#e6d0a8"],
		"count": 6,
		"seed": 8,
	},
}

const RISE := 0.11
const SINK := 0.36


static func _cx(u: float, x: float, lean: float, hook: float) -> float:
	return x + lean * u + hook * pow(u, 2.4)


static func _hw(u: float, w: float) -> float:
	return (w / 2.0) * pow(1.0 - u, 0.9) + 0.25


static func _in(px: int, py: int, base: float, h: float, x: float, lean: float, hook: float, w: float) -> bool:
	var u := (base - (py + 0.5)) / h
	if u < 0.0 or u > 1.0 or py + 0.5 > 0.0:
		return false
	var c := _cx(u, x, lean, hook)
	var fx := px + 0.5
	return absf(fx - c) <= _hw(u, w)


# a hooked thorn: a hardwood horn tapering from its foot, its point hooked forward; lit down its left edge with a
# bright ridge, shaded on the right, grain running up it, a pale point, a barb off its back, a dark rim
static func thorn(p: Px.Painter, s: Dictionary, h: float, C: Array, opts: Dictionary) -> void:
	if h < 1.5:
		return
	var x: float = s.x
	var w: float = s.w
	var hook: float = s.hook
	var lean: float = s.lean
	var base: float = opts.get("base", 0.0)
	var white: bool = opts.get("white", false)
	var X0 := floori(x - w - 6.0)
	var X1 := ceili(x + w / 2.0 + absf(lean) + absf(hook) + 2.0)
	for py in range(floori(base - h) - 1, mini(0, ceili(base)) + 1):
		for px in range(X0, X1 + 1):
			if not _in(px, py, base, h, x, lean, hook, w):
				if py <= 0 and (_in(px - 1, py, base, h, x, lean, hook, w) or _in(px + 1, py, base, h, x, lean, hook, w) or _in(px, py + 1, base, h, x, lean, hook, w) or _in(px, py - 1, base, h, x, lean, hook, w)):
					p.dot(px, py, C[0], opts.get("a", 1.0))
				continue
			if white:
				p.px(px, py, WHITE)
				continue
			var u := (base - (py + 0.5)) / h
			var c := _cx(u, x, lean, hook)
			var r := _hw(u, w)
			var q := (px + 0.5 - (c - r)) / (2.0 * r)
			var i := 4 if q < 0.0 else (6 if q < 0.16 else (5 if q < 0.36 else (7 if q < 0.46 else (4 if q < 0.7 else (3 if q < 0.86 else 2)))))
			if u > 0.86:
				i = 7 if q < 0.6 else 5
			if i < 7 and i > 2 and Px.rand(px, floori((py + 0.5 - base) / 3.0), s.seed) < 0.12:
				i -= 1
			p.px(px, py, C[i])
	# a barb off its back, raking up and away
	if not white and h > 14.0:
		var u0 := 0.34
		var u1 := 0.46
		var y0 := base - u0 * h
		var y1 := base - u1 * h
		var e0 := _cx(u0, x, lean, hook) - _hw(u0, w)
		var e1 := _cx(u1, x, lean, hook) - _hw(u1, w)
		var L := w * 0.45
		if y0 <= 0.0:
			p.tri(e0 + 0.5, y0, e1 + 0.5, y1, e1 - L, y1 - L * 0.7, C[3])
			p.line(e1, y1, e1 - L, y1 - L * 0.7, C[6])
			p.px(e1 - L, y1 - L * 0.7, C[7])
			p.line(e0, y0 + 1.0, e1 - L + 1.0, y1 - L * 0.7 + 1.0, C[0])


var C: Array
var G: Array
var S: Array
var R: Px.Rng
var n: float
var ps: Px.Particles
var lights: Px.Lights
var chips: Array
var list: Array
var reach: float
var t := 0.0


func create(o: Dictionary) -> void:
	C = Px.fit(o.palette, 8)
	G = Px.fit(o.glow, 4)
	S = Px.fit(o.soil, 8)
	R = Px.Rng.new(o.seed)
	var floor_ := func(): return 0.0
	n = maxf(2.0, o.count)
	ps = Px.Particles.new({"rng": R, "ground": floor_, "sparks": [G[3], G[2], G[1], G[0]]})
	lights = Px.Lights.new()
	chips = []
	list = Px.arr(n, func(i: int) -> Dictionary:
		var k := i / (n - 1.0)
		var h := 12.0 + 36.0 * k + R.range(-1.5, 1.5)
		return {"x": 10.0 + i * (104.0 / (n - 1.0)) + R.range(-3.0, 3.0), "h": h, "w": 6.0 + 9.0 * k, "lean": R.range(-1.0, 1.5) + k * 2.0, "hook": h * R.range(0.14, 0.22), "at": 0.12 + i * 0.075, "sink": 1.45 + i * 0.06, "seed": R.int_(1, 999), "up": false, "down": false})
	reach = list[int(n) - 1].x + 8.0
	t = 0.0


func chip(x: float, sp: float, nn: float) -> void:
	var i := 0
	while i < nn:
		var a := -PI / 2.0 + R.range(-1.1, 1.1)
		var v := R.range(60.0, 210.0) * sp
		chips.append({"x": x + R.range(-3.0, 3.0), "y": -1.0, "vx": cos(a) * v, "vy": sin(a) * v, "a": R.range(0.0, TAU), "va": R.range(-15.0, 15.0), "s": R.range(1.3, 2.6) * sqrt(sp), "pts": Lib.stoneShape(R), "life": minf(R.range(0.7, 1.1), meta.duration - 0.05 - t)})
		i += 1


func grown(s: Dictionary) -> float:
	return 0.0 if t < s.at else Px.Ease.outBack(Px.clamp((t - s.at) / RISE), 2.4)


func sunk(s: Dictionary) -> float:
	return Px.smooth(s.sink, s.sink + SINK, t)


func update(dt: float) -> void:
	t += dt
	var f := minf(1.0, dt * 120.0)
	for s: Dictionary in list:
		var k: float = s.h / 48.0
		if not s.up and t >= s.at:
			s.up = true
			lights.add(s.x, -s.h * 0.5, 18.0 + 18.0 * k, WHITE, 0.45, 0.08)
			lights.add(s.x, -s.h * 0.4, 26.0 + 26.0 * k, G[2], 0.45, 0.4)
			chip(s.x, 0.6 + 0.6 * k, 3.0 + Px.round(5.0 * k))
			var i := 0
			while i < 10.0 + 18.0 * k:
				var a := -PI / 2.0 + R.range(-1.0, 1.0)
				var v := R.range(60.0, 230.0) * (0.6 + 0.6 * k)
				ps.spawn(P.GRIT, s.x + R.range(-s.w / 3.0, s.w / 3.0), -1.0, cos(a) * v, sin(a) * v, R.range(0.6, 1.1), R.pick([S[5], S[4], S[3]]), 2.0 if R.chance(0.3) else 1.0)
				i += 1
			i = 0
			while i < 3.0 + 5.0 * k:
				ps.spawn(P.SMOKE, s.x + R.range(-4.0, 4.0), -R.range(1.0, 4.0), R.sign() * R.range(20.0, 80.0), -R.range(5.0, 25.0), R.range(0.7, 1.2), S[5], R.range(3.0, 5.5) * (0.6 + 0.5 * k), 0.0, 0)
				i += 1
			i = 0
			while i < 2.0 + 3.0 * k:
				ps.spawn(P.STAR, s.x + s.hook * 0.8 + R.range(-3.0, 3.0), -s.h * R.range(0.5, 1.0), R.range(-10.0, 10.0), -R.range(5.0, 20.0), R.range(0.3, 0.6), G[3], R.range(0.8, 2.0), R.range(0.0, 0.12))
				i += 1
			for j in 4:
				ps.spawn(P.MOTE, s.x + R.range(-3.0, 3.0), -R.range(2.0, s.h * 0.6), R.range(-20.0, 20.0), -R.range(30.0, 70.0), R.range(0.4, 0.8), G[3], 0.7)
		if not s.down and t >= s.sink:
			s.down = true
			chip(s.x, 0.35, 2.0 + Px.round(2.0 * k))
			var i := 0
			while i < 3.0 + 3.0 * k:
				ps.spawn(P.DUST, s.x + R.range(-s.w / 2.0, s.w / 2.0), -R.range(0.0, 3.0), R.sign() * R.range(15.0, 50.0), -R.range(2.0, 10.0), minf(R.range(0.4, 0.7), meta.duration - 0.05 - t), S[5], R.range(2.0, 4.0))
				i += 1
		# while they stand, glints run up their lit edges
		if s.up and not s.down and t > s.at + 0.2 and R.chance(0.05 * f):
			ps.spawn(P.STAR, s.x + s.lean * 0.5 - s.w * 0.15, -s.h * R.range(0.3, 0.8), 0.0, -3.0, R.range(0.25, 0.45), C[7], R.range(0.8, 1.8))
	var i := chips.size() - 1
	while i >= 0:
		var c: Dictionary = chips[i]
		c.life -= dt
		if c.life <= 0.0:
			chips.remove_at(i)
		c.vy += 950.0 * dt
		c.x += c.vx * dt
		c.y += c.vy * dt
		c.a += c.va * dt
		if c.y > 0.0 and c.vy > 0.0:
			if c.vy > 120.0:
				c.y = 0.0
				c.vy *= -0.3
				c.vx *= 0.6
				c.va *= 0.5
			else:
				c.y = 0.0
				c.va = 0.0
				c.vx = 0.0
				c.vy = 0.0
		i -= 1
	ps.update(dt)
	lights.update(dt)


func drawBack(p: Px.Painter) -> void:
	# the seam racing ahead along the floor: a dark split with a green glow in it, closing up again at the end
	var run := Px.Ease.outCubic(Px.clamp((t - 0.04) / 0.5)) * reach
	var fade := 1.0 - Px.smooth(1.9, 2.3, t)
	var x := -2
	while x <= run:
		var hot := Px.clamp(1.0 - (run - x) / 18.0) * (1.0 - Px.smooth(0.6, 1.2, t))
		var h := Px.rand(x, 31)
		p.dot(x, 0.0, G[3] if hot > 0.4 else (G[2] if hot > 0.1 else S[0]), fade)
		if h < 0.5:
			p.dot(x, 1.0, S[1], fade * 0.8)
		if h < 0.15:
			p.dot(x, -1.0, S[4], fade)
		if hot > 0.3 and (x & 3) == 0:
			p.glow(x, 0.0, 6.0, G[2], 0.3 * hot)
		x += 1
	ps.draw(p, "back")


func draw(p: Px.Painter) -> void:
	for s: Dictionary in list:
		var g := grown(s)
		var k := sunk(s)
		if g <= 0.0 or k >= 1.0:
			continue
		thorn(p, s, s.h * g, C, {"white": t - s.at < 0.035, "base": k * s.h * 1.05})
		if t - s.at < 0.3:
			p.glow(s.x, -s.h * 0.5 * g, s.h * 0.6 + 6.0, G[2], 0.35 * (1.0 - (t - s.at) / 0.3))
		# a collar of leaves round its foot, unfurling as it comes up and folding away as it sinks
		var lk := Px.clamp((t - s.at - 0.04) / 0.18) * (1.0 - k)
		var lw: float = s.w * 0.5
		if lk > 0.05:
			for q: Array in [[-1, -2.5, 1.0], [1, -0.55, 0.9], [-1, -1.9, 0.7]]:
				var sd: float = q[0]
				var a0: float = q[1]
				var sz: float = q[2]
				var la: float = a0 + sd * 0.25 * (1.0 - lk) + sin(t * 4.0 + s.x) * 0.06
				var L: float = (5.0 + s.w * 0.45) * sz * lk
				Lib.drawLeaf(p, s.x + sd * lw + cos(la) * L * 0.5, -1.0 + sin(la) * L * 0.5, L, 1.4 + s.w * 0.1 * sz, la, 0.35, [G[0], G[1], G[2], G[3]])
		p.glow(s.x, -2.0, s.w + 6.0, G[2], 0.18 * lk)
	for c: Dictionary in chips:
		Lib.drawRock(p, c.x, c.y, c.s, c.a, c.pts, S, minf(1.0, c.life / 0.25))
	ps.draw(p, "front")
	lights.draw(p)
