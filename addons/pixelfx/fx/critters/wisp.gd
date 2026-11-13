# The flame tail, puffs and embers are adapted from Sprite Fusion's open-source fire
# (https://www.spritefusion.com/pixel-art-vfx/fire), MIT License, Copyright (c) 2026 Hugo Duprez.
# port-of: src/fx/critters/wisp.js@64e55041da44c6ca073ee889a067d5eb03f133fb
extends RefCounted

const Px := preload("../../core/px.gd")
const Lib := preload("_lib.gd")
const P := Px.P

static var meta := {
	"name": "Wisp",
	"desc": "A will-o'-the-wisp loops a figure-eight over the floor: a little soul-flame with a face, its flame tail licking up and streaming behind, shedding puffs and sparks.",
	"tags": ["critter", "wisp", "spirit", "flame", "magic", "flying", "loop"],
	"size": [128, 104],
	"origin": [64, 96],
	"duration": 3.2,
	"loop": true,
	"fps": 30,
	"bg": "ground",
	"options": {"palette": ["#0a1f2e", "#0f3d52", "#14707e", "#1fa8a8", "#4fe0c8", "#a8fff0", "#ffffff"], "hover": 36, "seed": 1},
}

static var D: float = meta.duration
static var SWARM := Lib.Swarm.new()


static func at(t: float, hover: float) -> Dictionary:
	var a := (t / D) * TAU
	return {"x": 34.0 * sin(a), "y": -hover - 10.0 * sin(2.0 * a), "vx": ((34.0 * TAU) / D) * cos(a), "vy": ((-20.0 * TAU) / D) * cos(2.0 * a)}


static func draw(p: Px.Painter, time: float, o: Dictionary) -> void:
	var t := Lib.shift(time, D, o.seed)
	var C := Px.fit(o.palette, 7)
	var S := at(t, o.hover)
	var heat := [C[6], C[6], C[5], C[5], C[4], C[4], C[3], C[3], C[3]]
	var lean := Px.clamp(-S.vx / 80.0, -0.9, 0.9)
	var stretch := Px.clamp(S.vy / 120.0, -0.3, 0.4)
	var X: float = S.x
	var Y: float = S.y
	# flame puffs shed along its path, cooling down the ramp as they drift up
	Px.cycle(t, D, 30, o.seed * 7 + 1, func(r): return r.range(0.3, 0.6), func(age, L, r):
		var S0 := at(Px.wrap(t - age, D), o.hover)
		var xy := Px.fly(S0.x + r.range(-3.0, 3.0), S0.y - r.range(0.0, 4.0), r.range(-8.0, 8.0), -r.range(6.0, 16.0), age, -40.0, 2.5)
		Lib.firePuff(p, xy[0], xy[1], 1.0 - age / L, r.range(1.2, 2.6), r.next() * 100.0, heat))
	# the tail: three tongues off the top of its head, streaming back as it flies
	var tails := [[-3.5, 13.0, 2.5, 3.0], [3.5, 14.0, 2.5, 7.0], [0.0, 20.0, 3.2, 11.0]]
	for li in 4:
		for q in tails:
			var dx: float = q[0]
			var h: float = q[1]
			var w: float = q[2]
			var n: float = q[3]
			var hh := (h + 0.25 * h * Lib.lnoise(t, D, 9.0, n, 5)) * (1.0 + stretch)
			Lib.tongue(p, X + dx, Y - 2.0, hh, w, Lib.lnoise(t, D, 6.0, n, 40) * 1.5 + lean * hh * 0.9, t, D, n, heat, li)
	# the head: a ball of cold fire, white at the heart, its rim flickering
	var R := 7.5
	p.shade(X - R - 2.0, Y - R - 2.0, X + R + 2.0, Y + R + 2.0, func(x, y, out):
		var dx: float = x - X
		var dy: float = y - Y
		var ang := atan2(dy, dx)
		var rr := R + 0.7 * Lib.lnoise(t, D, 16.0, ang * 1.6 + 10.0, 3) + (-0.6 if dy > 0.0 else 0.0)
		var d := Px.hypot(dx, dy) / rr
		if d > 1.0:
			return 0
		return C[6] if d < 0.42 else (C[5] if d < 0.68 else (C[4] if d < 0.88 else C[3])))
	# its face: eyes looking where it's going, a blink, a little mouth
	var look := Px.round(Px.clamp(S.vx / 60.0, -1.0, 1.0))
	var blink := Px.wrap(t, D) > 2.2 and Px.wrap(t, D) < 2.28
	for s in [-1.0, 1.0]:
		var ex: float = Px.round(X) + s * 2.0 - (0.0 if s > 0.0 else 1.0) + look
		var ey := Px.round(Y) - 1.0
		if blink:
			p.px(ex, ey + 1.0, C[1])
			p.px(ex + 1.0, ey + 1.0, C[1])
		else:
			for k in 3:
				p.px(ex, ey + k, C[1])
				p.px(ex + 1.0, ey + k, C[1])
			p.px(ex + (1.0 if look > 0.0 else 0.0), ey, C[6])
	p.px(Px.round(X) + look, Px.round(Y) + 3.0, C[2])
	p.px(Px.round(X) - 1.0 + look, Px.round(Y) + 3.0, C[2])
	# sparks wander up off it
	var sw: Lib.Swarm = SWARM.begin(t)
	sw.ps.sparks = [C[6], C[5], C[4], C[3]]
	Px.cycle(t, D, 26, o.seed * 7 + 2, func(r): return r.range(0.8, 1.6), func(age, L, r):
		var S0 := at(Px.wrap(t - age, D), o.hover)
		var s: float = r.next() * 100.0
		var xy := Px.fly(S0.x + r.range(-5.0, 5.0), S0.y - r.range(4.0, 12.0), r.range(-20.0, 20.0), -r.range(20.0, 45.0), age, -15.0, 1.6)
		sw.add(P.EMBER, xy[0] + sin(age * 2.3 + s) * 3.0 * minf(1.0, age), xy[1], 0.0, 0.0, age, L, C[4], 2.0 if r.chance(0.3) else 1.0, 0, s))
	sw.draw(p)
	# light: a cold glow round it, a hot heart
	var fl := 0.85 + 0.15 * Lib.lnoise(t, D, 22.0, 0.0, 9)
	p.glow(X + lean * 3.0, Y - 6.0, 46.0 * fl, C[4], 0.38)
	p.glow(X, Y - 1.0, 13.0, C[5], 0.35 * fl)


static func drawBack(p: Px.Painter, time: float, o: Dictionary) -> void:
	var t := Lib.shift(time, D, o.seed)
	var C := Px.fit(o.palette, 7)
	var S := at(t, o.hover)
	var near := Px.clamp(1.0 - (-S.y - 24.0) / 30.0)
	# the floor lit cold beneath it, brighter as it dips
	Lib.shadow(p, S.x, 0.0, 7.0, 1.2, C[0], 0.4)
	for x in range(-24, 25, 6):
		p.glow(S.x + x, -1.0, 16.0, C[4], (0.08 + 0.1 * near) * (1.0 - absf(x) / 32.0))
