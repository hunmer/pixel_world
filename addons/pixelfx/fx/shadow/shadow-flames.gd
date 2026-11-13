# Tongues built from nested layers, each narrower and shorter than the last, are adapted from Sprite Fusion's
# open-source fire (https://www.spritefusion.com/pixel-art-vfx/fire), MIT License, Copyright (c) 2026 Hugo Duprez.
# Here the layers run the other way: a pale skin outside, violet within, a black heart at the core.
# port-of: src/fx/shadow/shadow-flames.js@e1228257fcc5af65dba6014b69afcf6f6b287bac
extends RefCounted

const Px := preload("../../core/px.gd")
const Lib := preload("_lib.gd")
const WHITE := Px.WHITE

static var meta := {
	"name": "Shadow flames",
	"desc": "Inside-out fire on the floor: a black heart wrapped in violet flame with pale skin and tips, shedding embers and dark smoke.",
	"tags": ["shadow", "fire", "flame", "ground", "dark", "magic", "loop"],
	"size": [104, 112],
	"origin": [52, 102],
	"duration": 2.4,
	"loop": true,
	"fps": 30,
	"bg": "ground",
	"options": {"palette": Lib.VOID, "seed": 12},
}

const D := 2.4
const GX := 22
const GY := 60
# tongues: offset, base height, width, seed; the middle tallest
const TONGUES := [[-11.0, 20.0, 4.2, 1], [11.0, 22.0, 4.4, 2], [-6.0, 31.0, 5.4, 3], [6.0, 29.0, 5.2, 4], [0.0, 40.0, 6.6, 5]]
# layers from the outside in: width share, height share, which tone (3 is the black heart)
const LAYERS := [[1.0, 1.0, 0], [0.8, 0.88, 1], [0.54, 0.68, 2], [0.32, 0.48, 3]]


# noise that comes back to where it started each loop: a circle through 2D noise, offset by v
static func lnoise(t: float, v: float, seed: Variant, speed: float = 5.0) -> float:
	return Px.noise2(cos((TAU * t) / D) * speed + v, sin((TAU * t) / D) * speed, seed)


static func drawBack(p: Px.Painter, t: float, o: Dictionary) -> void:
	var C := Px.fit(o.palette, 8)
	var S: float = o.seed
	# the scorched floor: a dark burn, violet light pooled on it
	p.ellipse(0.0, 0.5, 22.0, 3.2, func(d): return C[0] if d < 0.6 else C[1], func(d): return 1.0 if d < 0.85 else (1.0 - d) * 6.0)
	p.glow(0.0, -2.0, 46.0, C[4], 0.3)
	# dark smoke climbing off the tips, a lit rim on its underside
	Px.cycle(t, D, 14, S + 1.0, func(r): return r.range(1.2, 1.9), func(age, L, r):
		var u: float = age / L
		var x: float = r.range(-6.0, 6.0) + sin(u * 4.0 + r.range(0.0, 6.0)) * 5.0 * u
		var y: float = -30.0 - u * r.range(36.0, 52.0)
		var rad := 3.0 + u * 6.0
		var a := minf(1.0, u * 6.0) * (1.0 - u) * 0.7
		p.disc(x, y, rad, Px.mix(Px.mix(C[3], C[2], 0.5), C[1], u), a)
		p.disc(x - rad * 0.2, y - rad * 0.3, rad * 0.5, C[3], a * 0.4)
		p.disc(x, y + rad * 0.45, rad * 0.55, C[5], a * 0.45 * (1.0 - u)))


static func draw(p: Px.Painter, t: float, o: Dictionary) -> void:
	var C := Px.fit(o.palette, 8)
	var S: float = o.seed
	var TONE := [C[6], C[4], C[2], C[0]]
	# rasterize the tongues, outermost first, into a grid of tones
	var grid := PackedInt32Array()
	grid.resize(GX * 2 * GY)
	grid.fill(-1)
	var set_ := func(x: float, y: float, v: int) -> void:
		var i := Px.roundi(x) + GX
		var j := Px.roundi(y) + GY
		if i >= 0 and j >= 0 and i < GX * 2 and j < GY:
			grid[j * GX * 2 + i] = v
	var order := Px.arr(TONGUES.size(), func(i): return i)
	Px.sort(order, func(a, b): return absf(TONGUES[b][0]) - absf(TONGUES[a][0]))
	for i: int in order:
		var dx: float = TONGUES[i][0]
		var H0: float = TONGUES[i][1]
		var w: float = TONGUES[i][2]
		var n: int = TONGUES[i][3]
		var h := H0 * (0.78 + 0.22 * lnoise(t, n * 3, n, 4.0))
		var sway := lnoise(t, n * 7, n + 9, 3.0) * 3.0
		for layer: Array in LAYERS:
			var lw: float = layer[0]
			var lh: float = layer[1]
			var tone: int = layer[2]
			var Hl := h * lh
			var r := 0
			while r <= Hl:
				var u := r / maxf(1.0, Hl)
				var half := w * lw * pow(1.0 - u, 0.85) * minf(1.0, (r + 1.5) / 3.5) + lnoise(t, r * 0.45 + n, n + 20, 6.0) * 1.1 + lnoise(t, r * 1.3 + n * 5, n + 50, 9.0) * 0.6
				var cx := dx + sway * u * u * lh + lnoise(t, r * 0.2 + n * 2, n + 30, 5.0) * u * 1.4
				if half < 0.3:
					r += 1
					continue
				var x := Px.round(cx - half)
				while x <= Px.round(cx + half):
					# the skin breaks up near the top: pixels flicker out of it
					if tone == 0 and u > 0.45 and lnoise(t, x * 0.9 + r * 0.7 + n, n + 60, 8.0) > 0.35:
						x += 1.0
						continue
					set_.call(x, -r, tone)
					x += 1.0
				r += 1
	# draw it: the pale skin whitening to its tips, the black heart pure black
	for j in GY:
		for i in GX * 2:
			var v := grid[j * GX * 2 + i]
			if v < 0:
				continue
			var x := i - GX
			var y := j - GY
			var c: int = TONE[v]
			if v == 0 and y < -24 and (grid[(j - 1) * GX * 2 + i] if j > 0 else -1) < 0:
				c = WHITE if y < -32 else C[7]
			p.px(x + 0.5, y + 0.5, c)
	# licks of pale flame breaking off the tips
	Px.cycle(t, D, 34, S, func(r): return r.range(0.25, 0.5), func(age, L, r):
		var u: float = age / L
		var k: int = r.int_(0, 4)
		var dx: float = TONGUES[k][0]
		var H0: float = TONGUES[k][1]
		var x: float = dx + r.range(-4.0, 4.0) + u * r.range(-5.0, 5.0)
		var y: float = -H0 * r.range(0.45, 0.85) - u * r.range(10.0, 20.0)
		var rad: float = r.range(1.0, 2.2) * (1.0 - u) + 0.3
		p.circle(x, y, rad + 0.6, C[6] if u < 0.5 else C[4])
		if rad > 1.0:
			p.circle(x, y + 0.4, rad * 0.5, C[2] if u < 0.3 else C[4]))
	# embers drifting up, flickering, cooling to violet
	Px.cycle(t, D, 30, S + 2.0, func(r): return r.range(1.0, 1.8), func(age, L, r):
		var u: float = age / L
		var x: float = r.range(-12.0, 12.0) + sin(u * 6.0 + r.range(0.0, 6.0)) * 5.0 * u
		var y: float = -10.0 - u * r.range(40.0, 70.0)
		if u > 0.7 and sin(age * 40.0 + x) < 0.0:
			return
		p.px(x, y, WHITE if u < 0.3 else (C[7] if u < 0.6 else C[6]))
		p.glow(x, y, 3.0, C[6], 0.35 * (1.0 - u)))
	# light: a violet bloom round it, but none on the black heart
	var fl := 0.85 + 0.15 * lnoise(t, 0.0, 77, 6.0)
	p.glow(0.0, -16.0, 52.0, C[4], 0.5 * fl)
	p.glow(0.0, -12.0, 26.0, C[6], 0.34 * fl)
	for j in GY:
		for i in GX * 2:
			if grid[j * GX * 2 + i] == 3:
				var sx := p.cellX(i - GX + 0.5, j - GY + 0.5) - p.ox
				var sy := p.cellY(i - GX + 0.5, j - GY + 0.5) - p.oy
				if sx >= 0 and sy >= 0 and sx < p.w and sy < p.h:
					p.L[sy * p.w + sx] = 0
