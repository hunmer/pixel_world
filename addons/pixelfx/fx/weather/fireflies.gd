# The firefly (a wandering point that glows up and fades on its own rhythm, close ones drawn with a dark body,
# beating wings and a lantern that throws a big soft light, grass blades swaying underneath) is adapted from
# Sprite Fusion's open-source fireflies (https://www.spritefusion.com/pixel-art-vfx/fireflies), MIT License,
# Copyright (c) 2026 Hugo Duprez.
# port-of: src/fx/weather/fireflies.js@25511900cc17f40531342253430ea82206f2db98
extends RefCounted

const Px := preload("../../core/px.gd")
const Lib := preload("_lib.gd")

static var meta := {
	"name": "Fireflies",
	"desc": "Fireflies wander over a meadow at night, each glowing up and fading on its own rhythm, trailing light and lighting the grass tips beneath them.",
	"tags": ["weather", "fireflies", "night", "glow", "meadow", "nature", "ambient", "loop"],
	"size": [320, 180],
	"origin": [160, 170],
	"duration": 12.0,
	"loop": true,
	"fps": 30,
	"bg": "sky",
	"options": {
		"palette": ["#2a3a10", "#5a7a1a", "#9ad02a", "#d6ff5a", "#f4ffb8", "#ffffff"],
		"grass": ["#070f0b", "#0c1a12", "#13281a", "#1d3a24", "#2b5232", "#3f6e40"],
		"seed": 2,
	},
}

const D := 12.0


static func cyc(t: float, n: float, ph: float = 0.0) -> float:
	return (TAU * n * t) / D + ph


# a firefly's path and glow, both whole cycles a loop. depth 0 far .. 2 near
static func fly(S: float, i: int, t: float) -> Dictionary:
	var R := func(n): return Px.rand(S, i, n)
	var depth := 0 if i < 14 else (1 if i < 26 else 2)
	var k: float = [0.5, 0.8, 1.0][depth]
	var cx: float = -150 + R.call(1) * 300
	var cy: float = -16 - R.call(2) * (70 if depth == 2 else 130)
	var ax: float = (14 + R.call(3) * 26) * k
	var ay: float = (8 + R.call(4) * 14) * k
	var n1: float = 1 + floorf(R.call(5) * 2)
	var n2: float = 1 + floorf(R.call(6) * 3)
	var pos := func(tt: float) -> Array: return [
		cx + ax * sin(cyc(tt, n1, R.call(7) * TAU)) + 10 * k * Px.loopNoise(tt / D, 1.5, i * 3),
		cy + ay * sin(cyc(tt, n2, R.call(8) * TAU)) + 6 * k * Px.loopNoise(tt / D, 1.5, i * 3 + 1),
	]
	# its rhythm: a quick rise, a hold, a slow fade, dark; some flash twice
	var per: float = D / (3 + floorf(R.call(9) * 4))
	var u := fmod(fmod(t / per + R.call(10), 1.0) + 1, 1.0)
	var two: bool = R.call(11) < 0.35
	var glow := maxf(pulse(u), pulse(u - 0.22) * 0.8 if two else 0.0)
	return {"pos": pos, "depth": depth, "glow": glow, "R": R}


static func pulse(v: float) -> float:
	return v / 0.06 if v < 0.06 else (1.0 if v < 0.14 else (1 - (v - 0.14) / 0.26 if v < 0.4 else 0.0))


static func drawBack(p: Px.Painter, t: float, o: Dictionary) -> void:
	var q := Lib.clip(p, meta)
	var S: float = o.seed
	var C := Px.fit(o.palette, 6)
	var G := Px.fit(o.grass, 6)
	# a cool night haze, so the sky's stars don't read as fireflies
	Lib.rows(p, meta, -170, 9, func(y: float, R: Lib.Row) -> void:
		var k := (y + 170) / 180
		R.c.fill(Px.mix(G[0], G[1], k))
		R.a.fill(0.48 + 0.14 * k)
		R.b.fill(1))
	var flies := Px.arr(32, func(i): return fly(S, i, t))
	grass(q, t, S, G, C, flies, false)
	for f: Dictionary in flies:
		if f.depth < 2:
			firefly(q, t, f, C)


static func draw(p: Px.Painter, t: float, o: Dictionary) -> void:
	var q := Lib.clip(p, meta)
	var S: float = o.seed
	var C := Px.fit(o.palette, 6)
	var G := Px.fit(o.grass, 6)
	var flies := Px.arr(32, func(i): return fly(S, i, t))
	grass(q, t, S, G, C, flies, true)
	for f: Dictionary in flies:
		if f.depth == 2:
			firefly(q, t, f, C)


static func firefly(q: Px.Painter, t: float, f: Dictionary, C: Array) -> void:
	var xy: Array = f.pos.call(t)
	var x: float = xy[0]
	var y: float = xy[1]
	var g: float = f.glow
	var X := Px.round(x)
	var Y := Px.round(y)
	if f.depth == 0:
		if g < 0.08:
			return
		q.dot(X, Y, C[4] if g > 0.6 else C[3], minf(1, g * 1.6))
		q.glow(x, y, 6, C[2], 0.45 * g)
		return
	# a short trail of light where it has just been, while it's lit
	if g > 0.3:
		for j in range(1, 5):
			var txy: Array = f.pos.call(t - j * 0.05)
			q.dot(txy[0], txy[1], C[2], (g - 0.3) * (1 - j / 5.0) * 1.3)
	if f.depth == 1:
		q.px(X, Y, C[5] if g > 0.5 else (C[3] if g > 0.15 else C[1]))
		if g > 0.4:
			q.px(X, Y + 1, C[2])
		q.glow(x, y, 9, C[2], 0.5 * g)
		q.glow(x, y, 3, C[4], 0.5 * g)
		return
	# a close one: a dark body, wings a blur above it, a lantern at its tail; a glint at the peak
	var nx: float = f.pos.call(t + 0.05)[0]
	var dir := 1 if nx >= x else -1
	var beat := int(floorf(t * 30)) % 2
	q.px(X + dir, Y, C[0])
	q.px(X + dir * 2, Y, C[0])
	q.dot(X, Y - 1 - beat, Px.mix(C[1], Px.WHITE, 0.4), 0.7)
	q.dot(X + dir, Y - 1 - beat, Px.mix(C[1], Px.WHITE, 0.4), 0.7)
	q.px(X, Y, C[5] if g > 0.3 else C[1])
	q.px(X - dir, Y, C[4] if g > 0.5 else (C[3] if g > 0.15 else C[1]))
	if g > 0.6:
		q.px(X - dir, Y + 1, C[3])
	if g > 0.7:
		for dd: Array in [[0, -2], [0, 2], [-2, 0], [2, 0]]:
			q.dot(X - dir + dd[0], Y + dd[1], C[3], (g - 0.7) * 3)
	q.glow(x, y, 28, C[2], 0.45 * g)
	q.glow(x, y, 10, C[4], 0.5 * g)
	q.glow(x, y, 4, C[5], 0.5 * g)


# the meadow: blades in two rows (the front row drawn over the low fireflies), swaying as the breeze rolls
# across, a few seed heads; blade tips near a lit firefly catch its light
static func grass(q: Px.Painter, t: float, S: float, G: Array, C: Array, flies: Array, front: bool) -> void:
	var lit := flies.filter(func(f): return f.glow > 0.25 and f.depth > 0).map(func(f): return f.pos.call(t) + [f.glow])
	var n := 150 if front else 230
	for i in n:
		var R := func(k): return Px.rand(S * 3 + (1 if front else 0), i, k)
		var x: float = -162 + (i + R.call(1)) * (324.0 / n)
		var h: float = (4 if front else 5) + R.call(2) * (8 if front else 11) + (6 if R.call(3) < 0.1 else 0)
		var base: float = (9 if front else 2) - R.call(4) * 3
		var sway: float = (1.2 + R.call(5)) * sin(cyc(t, 2, -x * 0.03) + R.call(6)) + 0.6 * sin(cyc(t, 5, x * 0.07))
		var tone: int = 1 + floori(R.call(7) * 3) if front else 1 + floori(R.call(7) * 2)
		var tipLight := 0.0
		for fl: Array in lit:
			var fx: float = fl[0]
			var fy: float = fl[1]
			var g: float = fl[2]
			var d := Px.hypot(fx - (x + sway), fy - (base - h))
			if d < 28:
				tipLight = maxf(tipLight, g * (1 - d / 28))
		var r := 0
		while r < h:
			var u := r / h
			var c: int = ((C[3] if (tipLight > 0.55 and u > 0.9) else C[2]) if (u > 0.8 and tipLight > 0.2) else (G[mini(5, tone + 1)] if u > 0.7 else G[tone]))
			q.px(x + sway * u * u, base - r, c)
			r += 1
		if R.call(8) < 0.07:
			var sx := x + sway
			var sy := base - h
			q.px(sx, sy - 1, C[3] if tipLight > 0.2 else G[5])
			q.px(sx - 1, sy, G[4])
			q.px(sx + 1, sy, G[4])
