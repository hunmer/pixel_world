# Banded volumes with a lit crest (light on the top edge, tones stepping down into the body, Bayer at the steps)
# after Sprite Fusion's open-source fog (https://www.spritefusion.com/pixel-art-vfx/fog), MIT License,
# Copyright (c) 2026 Hugo Duprez.
# port-of: src/fx/weather/clouds.js@eb7454a67fbef6fd3f32f71c08f6cde8f1df4db3
extends RefCounted

const Px := preload("../../core/px.gd")
const Lib := preload("_lib.gd")

static var meta := {
	"name": "Clouds",
	"desc": "Layers of clouds drift past a bright moon at night: silver-lit tops, dark bellies, edges that flare where they cross the moon, forming and thinning as they go.",
	"tags": ["weather", "clouds", "moon", "night", "sky", "ambient", "loop"],
	"size": [320, 180],
	"origin": [160, 180],
	"duration": 12.0,
	"loop": true,
	"fps": 30,
	"bg": "sky",
	"options": {
		"palette": ["#0c0c18", "#16172a", "#232540", "#363a5a", "#545a80", "#8088ae", "#bcc4e2", "#f2f4ff"],
		"seed": 7,
	},
}

const D := 12.0
const MX := 92.0
const MY := -128.0
const MR := 12.0
# far to near: how many clouds, how wide, how tall their puffs, how high, drift speed, how long they live,
# tones [belly, body, upper, top], how see-through
const LAYERS := [
	{"n": 7, "w": [40.0, 70.0], "h": [6.0, 11.0], "y": [-150.0, -110.0], "v": 3.0, "life": [8.0, 11.0], "tone": [2, 3, 4, 5], "alpha": 0.7},
	{"n": 6, "w": [60.0, 100.0], "h": [9.0, 15.0], "y": [-120.0, -70.0], "v": 6.0, "life": [8.0, 11.0], "tone": [1, 2, 4, 6], "alpha": 0.88},
	{"n": 5, "w": [90.0, 140.0], "h": [12.0, 20.0], "y": [-80.0, -30.0], "v": 10.0, "life": [9.0, 12.0], "tone": [1, 2, 3, 6], "alpha": 1.0},
]


static func draw(p: Px.Painter, t: float, o: Dictionary) -> void:
	var q := Lib.clip(p, meta)
	var S: float = o.seed
	var C := Px.fit(o.palette, 8)
	moon(q, C)
	for j in LAYERS.size():
		var L: Dictionary = LAYERS[j]
		for i in L.n:
			cloud(q, t, S, C, L, j, i)
	# the moon's light over everything: a halo, brightest close in, catching any cloud that passes
	q.glow(MX, MY, 110, C[4], 0.14)
	q.glow(MX, MY, 40, C[5], 0.25)
	q.glow(MX, MY, 18, C[6], 0.3)


static func moon(q: Px.Painter, C: Array) -> void:
	q.shade(MX - MR - 1, MY - MR - 1, MX + MR + 1, MY + MR + 1, func(x: float, y: float, out) -> void:
		var dx := x - MX
		var dy := y - MY
		var d := Px.hypot(dx, dy) / MR
		if d > 1:
			return
		# a pale disc with darker seas, a bright limb on the lit side
		var sea := pow(dx + 4, 2) + pow(dy + 2, 2) < 14 or pow(dx - 3, 2) + pow(dy - 4, 2) < 9 or pow(dx - 5, 2) + pow(dy + 5, 2) < 4
		out.c = (C[6] if dx + dy < 0 else Px.WHITE) if d > 0.86 else (C[5] if sea else (Px.WHITE if (d < 0.5 and dx + dy < 0) else C[7])))


# one cloud: born once a loop, it swells into shape, drifts, and thins away. Its outline is a row of puffs on a
# flat base; shading steps down from a silver top to a dark belly, and edges near the moon flare
static func cloud(q: Px.Painter, t: float, S: float, C: Array, L: Dictionary, j: int, i: int) -> void:
	var R := func(k): return Px.rand(S, j, i, k)
	var life: float = L.life[0] + R.call(1) * (L.life[1] - L.life[0])
	var age := Px.wrap(t - R.call(2) * D, D)
	if age >= life:
		return
	var u := age / life
	var grow := minf(1, u * 4) * minf(1, (1 - u) * 4)
	var w: float = (L.w[0] + R.call(3) * (L.w[1] - L.w[0])) * (0.6 + 0.4 * grow)
	var x0: float = -200 + R.call(4) * 330 + L.v * age
	var base: float = L.y[0] + R.call(5) * (L.y[1] - L.y[0])
	var H: float = (L.h[0] + R.call(6) * (L.h[1] - L.h[0])) * grow
	if H < 1.5:
		return
	# a row of puffs along the base, and a tier of bigger ones heaped in the middle
	var n: float = 4 + floorf(R.call(7) * 4)
	var puffs := []
	for k in int(n):
		var f := (k + 0.5) / n
		var r: float = H * (0.5 + 0.35 * sin(PI * f)) * (0.75 + 0.5 * R.call(10 + k)) * (1 + 0.06 * sin((TAU * t) / D + k + i))
		puffs.append([x0 + w * (f - 0.5) + (R.call(20 + k) - 0.5) * 6, base - r * 0.3 - R.call(30 + k) * H * 0.15, r])
	var k := 0
	while k < 1 + floorf(R.call(8) * 3):
		var f: float = 0.3 + R.call(40 + k) * 0.4
		var r: float = H * (0.75 + 0.35 * R.call(50 + k)) * (1 + 0.05 * sin((TAU * t) / D + k * 2 + i))
		puffs.append([x0 + w * (f - 0.5), base - H * 0.55 - r * 0.2, r])
		k += 1
	var x1 := x0 - w / 2 - H
	var x2 := x0 + w / 2 + H
	var B := Lib.box(meta)
	var tone: Array = L.tone
	var alpha: float = L.alpha
	for x in range(int(maxf(B.x0, floorf(x1))), int(minf(B.x1 - 1, ceilf(x2))) + 1):
		var cx := x + 0.5
		var top := INF
		var top2 := INF
		for pf: Array in puffs:
			var px: float = pf[0]
			var py: float = pf[1]
			var r: float = pf[2]
			var dx := cx - px
			if dx * dx >= r * r:
				continue
			var y := py - sqrt(r * r - dx * dx)
			if y < top:
				top2 = top
				top = y
			elif y < top2:
				top2 = y
		if top == INF:
			continue
		# a belly that's nearly flat, lifting at the ends and rippling a little
		var end := minf(cx - x1, x2 - cx) / H
		var bot := base + 1.5 + sin(cx * 0.21 + i) * 0.8 - ((1 - end) * 4 if end < 1 else 0.0)
		if bot <= top:
			continue
		var h := bot - top
		var inner := floorf(top2) if (top2 - top > 2.5 and top2 < bot - 2) else -999.0
		var y := floorf(top)
		while y < bot:
			var d := y + 0.5 - top
			var v := d / h
			var th := Lib.bayer(x, y) * 0.12
			var md := Px.hypot(cx - MX, y - MY)
			var c: int = tone[3] if d < 1 else (tone[2] if v < 0.25 + th else (tone[1] if v < 0.62 + th else tone[0]))
			# the top of a lower puff shows inside the body as a lit line: the cloud's lobes
			if y == inner:
				c = maxi(c, tone[2])
			if bot - y - 0.5 < 1 and v > 0.5:
				c = maxi(0, tone[0] - 1)
			# the silver lining: near the moon the edges light right up
			if md < 46 and (d < 2 or y == inner or v < 0.3):
				c = mini(7, c + (2 if md < 24 else 1))
			var a := alpha * minf(1, grow * 1.5)
			if a >= 1:
				q.px(x, y, C[c])
			else:
				q.blend(x, y, C[c], a)
			if d < 1 and md < 46:
				q.light(x, y, C[6], 0.35 * (1 - md / 46))
			y += 1
