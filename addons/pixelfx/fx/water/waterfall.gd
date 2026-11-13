# The pool's caustic light (two warped sine nets, light where they cross zero) is adapted from Sprite Fusion's
# open-source bubbles (https://www.spritefusion.com/pixel-art-vfx/bubbles), MIT License, Copyright (c) 2026 Hugo Duprez.
# port-of: src/fx/water/waterfall.js@573def3e9b4e153aab3c58e5e931241cb0915f67
extends RefCounted

const Px := preload("../../core/px.gd")
const Lib := preload("_lib.gd")
const WHITE := Px.WHITE

static var meta := {
	"name": "Waterfall",
	"desc": "A river pours from a notch in a rock outcrop: a white curl, a deep sheet that splits into strands, churning foam, spray, drifting mist and rings on a dark pool.",
	"tags": ["water", "waterfall", "cascade", "foam", "mist", "ambient", "loop"],
	"size": [144, 136],
	"origin": [72, 118],
	"duration": 2,
	"loop": true,
	"fps": 30,
	"bg": "ground",
	"options": {"palette": Lib.WATER, "height": 92, "width": 13, "ledge": true, "seed": 5},
}

static var D: float = meta.duration
const SY := 0.2
const G := 760.0
const POOL := [56.0, 11.0]


# half the sheet's width at depth d below the lip: it spreads a little as it falls
static func halfW(W: float, d: float, H: float) -> float:
	return W + 3.2 * pow(Px.clamp(d / H), 1.6)


# the falling sheet, in 1 px lanes. Lanes on the far side of the fall are dark and see-through, so the night shows
# between strands; the front lanes carry white dashes sliding down them, stretching as the water speeds up (the
# texture runs in fall time, √depth). The top is glassy and dark, and the lower third splits into strands that
# fan apart with gaps between, each lit down its left edge.
static func sheet(p: Px.Painter, C: Array, ph: float, H: float, W: float, S: float) -> void:
	var y := -H + 2.0
	while y <= -1.0:
		var d := y + 0.5 + H
		var v := d / H
		var s := sqrt(d + 3.0)
		var hw0 := halfW(W, d, H)
		var split := Px.smooth(0.56, 0.95, v)
		var glass := 1.0 - Px.smooth(4.0, 24.0, d)
		var wl := Px.tileNoise(2.0, s * 1.4 - ph * 12.0, 0.0, 12.0, S + 2.0) * (0.4 + 1.8 * v)
		var wr := Px.tileNoise(11.0, s * 1.4 - ph * 12.0, 0.0, 12.0, S + 2.0) * (0.4 + 1.8 * v)
		var fan := Px.tileNoise(3.0, s * 0.8 - ph * 4.0, 0.0, 4.0, S + 61.0) * 1.6 if split > 0.0 else 0.0
		var sd := s * 1.5 - ph * 20.0
		var sb := s * 0.45 - ph * 6.0
		var X := -W - 8.0
		while X <= W + 8.0:
			var x := X + 0.5
			var hw := hw0 + (wl if x < 0.0 else wr)
			var ax := absf(x)
			if ax > hw:
				X += 1.0
				continue
			var e := ax / hw
			var edge := false
			if split > 0.0:
				var f := fmod(fmod((x / (1.0 + 0.22 * split) + fan + 64.0) / 5.4, 1.0) + 1.0, 1.0)
				if f > 1.0 - 0.46 * split:
					X += 1.0
					continue
				edge = f < 0.2
			var dash := Px.tileNoise(X * 1.618 + 0.31, sd, 0.0, 20.0, S)
			if Px.rand(X, S + 60.0) < 0.48 and e < 0.86 and not edge:
				p.blend(x, y + 0.5, C[4] if dash > 0.45 else (C[3] if glass > 0.5 else C[2]), 0.7 if dash > 0.45 else 0.42 + 0.15 * v)
				X += 1.0
				continue
			var broad := Px.tileNoise(floorf((x + 40.0) / 3.0) * 2.7, sb, 0.0, 6.0, S + 1.0)
			var b := -0.34 + 0.46 * v + 0.3 * broad - glass * 0.5 + 0.35 * Px.smooth(0.7, 1.0, e) * (1.0 if x < 0.0 else 0.3) - (0.12 * e if x > 0.0 else 0.0) + (0.3 if edge else 0.0)
			if dash > 0.2 - 0.22 * v:
				b += 0.36 + 0.7 * (dash - 0.2)
			if b > -0.2:
				p.px(X, y, WHITE if b > 0.62 else (C[6] if b > 0.34 else (C[5] if b > 0.08 else C[4])))
			else:
				p.blend(x, y + 0.5, C[3], 0.8)
			X += 1.0
		y += 1.0
	# strands peel off the edges and fall free
	Px.cycle(ph * D, D, 16, S + 30.0, 0.4, func(age: float, life: float, r: Px.Rng):
		var side := r.sign()
		var d0 := r.range(14.0, H * 0.7)
		var d := d0 + 50.0 * age + 260.0 * age * age
		var k := age / life
		if d > H - 6.0:
			return
		var x := side * (halfW(W, d, H) + 1.5 + age * r.range(6.0, 16.0))
		var yy := -H + d
		var len := 2.0 + 6.0 * k
		p.line(x, yy - len, x, yy, func(u: float): return C[6] if u > 0.7 else C[4], 1.0 - k * 0.5))


# the outcrop the river pours from: boulders shaded like the explosion's rocks (a lit top edge, shaded faces, a
# dark underside, a dark rim), creased where they meet, cracked; dark and glossy where the water runs over them
# which boulder is frontmost at each pixel of the outcrop, and how much light its face catches there
static var ROCKS := {}


static func rockMap(lumps: Array, x0: float, y0: float, w: int, hgt: int, Lx: float, Ly: float, Lz: float, S: float) -> Dictionary:
	var id := PackedInt32Array()
	id.resize(w * hgt)
	id.fill(-1)
	var lit := PackedFloat32Array()
	lit.resize(w * hgt)
	for j in hgt:
		for i in w:
			var x := x0 + i + 0.5
			var y := y0 + j + 0.5
			var best := -1
			var z := -1e9
			var l := 0.0
			for k in lumps.size():
				var lump: Array = lumps[k]
				var cx: float = lump[0]
				var cy: float = lump[1]
				var rx: float = lump[2]
				var ry: float = lump[3]
				var nx := (x - cx) / rx
				var ny := (y - cy) / ry
				var r2 := nx * nx + ny * ny
				if r2 >= 1.0:
					continue
				var nz := sqrt(1.0 - r2)
				var depth := nz * ry + (-6.0 if k == 5 else (-3.0 if k == 2 else (-1.0 if k > 2 else 0.0)))
				if depth > z:
					z = depth
					best = k
					l = nx * Lx + ny * Ly + nz * Lz
			id[j * w + i] = best
			lit[j * w + i] = l + 0.2 * Px.tileNoise(x * 0.32, y * 0.32, 0.0, 0.0, S + 70.0)
	return {"id": id, "lit": lit}


static func outcrop(p: Px.Painter, C: Array, ph: float, H: float, W: float, S: float) -> void:
	var ST := Lib.rock()
	var Lx := -0.55
	var Ly := -0.72
	var Lz := 0.42
	# [x, y, rx, ry]: a big boulder left of the notch, a smaller one right, the sill the water runs over, two feet,
	# and a slab behind that joins them, the notch cut into it
	var lumps := [[-W - 11.0, -H - 4.0, 13.0, 10.0], [W + 8.0, -H - 2.0, 9.0, 7.5], [0.0, -H + 3.5, W + 3.0, 4.2], [-W - 21.0, -H + 4.0, 7.0, 5.5], [W + 15.0, -H + 4.5, 5.0, 4.0], [-2.0, -H - 5.0, W + 7.0, 6.5]]
	var x0 := -W - 29.0
	var x1 := W + 21.0
	var y0 := -H - 15.0
	var y1 := -H + 10.0
	var w := int(x1 - x0 + 1.0)
	var hgt := int(y1 - y0 + 1.0)
	var key := "%s|%s|%s" % [W, H, S]
	var map: Variant = ROCKS.get(key)
	if not map:
		map = rockMap(lumps, x0, y0, w, hgt, Lx, Ly, Lz, S)
		ROCKS[key] = map
	var id: PackedInt32Array = map.id
	var lit: PackedFloat32Array = map.lit
	# a soft shadow under it on whatever is behind
	p.each(-W - 26.0, -H, W + 18.0, -H + 20.0, func(x: float, y: float, sx: int, sy: int):
		var k := 1.0 - Px.hypot((x + 4.0) / (W + 22.0), (y + H) / 20.0)
		if k > 0.0:
			p.blendPx(sx, sy, ST[0], 0.4 * minf(1.0, k * 3.0)))
	var at := func(i: float, j: float) -> int: return -1 if (i < 0.0 or j < 0.0 or i >= w or j >= hgt) else id[int(j) * w + int(i)]
	for j in hgt:
		for i in w:
			var k := id[j * w + i]
			var x := x0 + i
			var y := y0 + j
			# the river runs over the sill: nothing of the sill shows through it
			if (k == 2 or k == 5 or k < 0) and y >= -H - 5.0 and y < -H + 1.0 and absf(x + 0.5) < W + 1.5:
				continue
			if k < 0:
				if at.call(i - 1, j) >= 0 or at.call(i + 1, j) >= 0 or at.call(i, j - 1) >= 0 or at.call(i, j + 1) >= 0:
					p.px(x, y, ST[0])
				continue
			# a crease where one boulder sits in front of another
			var r: int = at.call(i + 1, j)
			var b: int = at.call(i, j + 1)
			if (r >= 0 and r != k and r < k) or (b >= 0 and b != k):
				p.px(x, y, ST[1])
				continue
			var l := lit[j * w + i]
			var wet := absf(x + 0.5) < W + 6.0 and y > -H - 9.0
			var c: int = ST[5] if l > 0.9 else (ST[4] if l > 0.64 else (ST[3] if l > 0.3 else (ST[2] if l > -0.05 else ST[1])))
			if k == 5:
				c = ST[3] if l > 0.7 else (ST[2] if l > 0.2 else ST[1])
			if at.call(i, j - 1) < 0 and l > 0.25:
				c = ST[5]
			if wet:
				# wet stone: a step darker, a cool gloss running down it where the light catches
				c = ST[4] if l > 0.9 else (ST[3] if l > 0.64 else (ST[2] if l > 0.3 else ST[1]))
				if l > 0.3 and Px.tileNoise(x * 0.9, y * 0.6 - ph * 8.0, 0.0, 8.0, S + 71.0) > 0.42:
					c = C[6] if l > 0.6 else C[4]
			p.px(x, y, c)
	# cracks: dark lines with a lit lip above them
	for q in 3:
		var L: Array = lumps[q % 2]
		var cx := floorf(L[0] + (-0.5 if q == 2 else 0.15) * L[2])
		var cy := floorf(L[1] + L[3] * (0.1 if q == 2 else -0.25))
		var len := 3.0 + floorf(Px.rand(q, S + 74.0) * 4.0)
		var dx := 1.0 if Px.rand(q, S + 75.0) < 0.5 else -1.0
		var n := 0
		while n <= len:
			var x := cx + Px.round(n * 0.6) * dx
			var y := cy + n
			var i := x - x0
			var j := y - y0
			if at.call(i, j) < 0 or at.call(i, j) > 1 or at.call(i, j + 1) < 0:
				break
			p.px(x, y, ST[1] if n == len else ST[0])
			if n == 0:
				p.px(x - dx, y - 1.0, ST[4])
			n += 1
	# trickles run down the wet faces either side of the notch
	for sx: float in [-W - 3.0, W + 3.0]:
		var y := -H - 2.0
		while y < -H + 7.0:
			var g := fmod(fmod(y * 0.35 - ph * 6.0, 1.0) + 1.0, 1.0)
			var i := floorf(sx) - x0
			var j := floorf(y) - y0
			if at.call(i, j) >= 0:
				p.px(sx, y, C[6] if g < 0.3 else C[3])
			y += 1.0


# the river sliding out of the notch between the boulders, seen from just above: flow lines sliding to the edge
static func river(p: Px.Painter, C: Array, ph: float, H: float, W: float, S: float) -> void:
	var top := -H - 6.0
	p.shade(-W - 3.0, top, W + 3.0, -H, func(x: float, y: float, out):
		var back := top + 1.5 + Px.tileNoise(x * 0.3, 4.0, 0.0, 0.0, S + 62.0) * 1.5
		var v := (y - back) / (-H - back)
		var hw := W + 2.0 - (1.0 - v) * 3.0
		if y < back or absf(x) > hw:
			return
		var n := Px.tileNoise(x * 0.32, (y - top) * 0.7 - ph * 8.0, 0.0, 8.0, S + 3.0)
		out.c = C[6] if n > 0.66 else (C[5] if n > 0.4 else (C[3] if v < 0.5 else C[4])))


# the curl over the edge: glassy blue as it rolls, a hard white line along the bend; its light on the stone
static func curl(p: Px.Painter, C: Array, ph: float, H: float, W: float, S: float) -> void:
	var x := -W
	while x <= W:
		var g := Px.tileNoise(x * 0.45, ph * 4.0, 0.0, 4.0, S + 4.0)
		p.px(x, -H - 1.0, C[4])
		p.px(x, -H, WHITE)
		p.px(x, -H + 1.0, C[6] if g > 0.2 else C[5])
		x += 1.0
	p.glowLine(-W, -H, W, -H, 6.0, C[6], 0.18)
	p.glow(0.0, -H, 34.0, C[5], 0.2)
	# glints run along it
	Px.cycle(ph * D, D, 4, S + 5.0, 0.36, func(age: float, life: float, r: Px.Rng):
		var k := sin((PI * age) / life)
		var gx := r.range(-W, W)
		if k > 0.5:
			for dd: Array in [[1, 0], [-1, 0], [0, 1], [0, -1]]:
				p.px(gx + dd[0], -H + dd[1], C[6])
		p.glow(gx, -H, 6.0, C[5], 0.4 * k))


# the pool: dark see-through water, a lit far rim, caustic light swimming in it, the falls' reflection
static func pool(p: Px.Painter, C: Array, ph: float, W: float, S: float) -> void:
	var RX: float = POOL[0]
	var RY: float = POOL[1]
	var cy := 2.0
	var T := ph * TAU
	var cols := []
	var X := -RX
	while X < RX:
		var x := X + 0.5
		cols.append([sin(x * 0.11 - T * 2.0), sin(T + x * 0.05) * 1.4 + x * 0.13])
		X += 1.0
	var Y := floorf(cy - RY)
	while Y < cy + RY:
		var y := Y + 0.5
		var dy := (y - cy) / RY
		var sy := sin(y * 0.5 + T)
		X = -RX
		while X < RX:
			var x := X + 0.5
			var dx := x / RX
			var d := dx * dx + dy * dy
			if d > 1.0:
				X += 1.0
				continue
			p.blend(x, y, C[2] if d < 0.12 else C[1], 0.62 * minf(1.0, (1.0 - d) * 4.0))
			# caustics: two warped sine nets, light where either crosses zero
			var cc: Array = cols[int(X + RX)]
			var cx1: float = cc[0]
			var cx2: float = cc[1]
			var u := x * 0.2 + 1.8 * sy
			var w := y * 0.55 + 1.8 * cx1
			var f := (maxf(0.0, 1.0 - absf(sin(u) + sin(w)) * 2.6) + 0.6 * maxf(0.0, 1.0 - absf(sin(cx2 + y * 0.3)) * 3.0)) * (1.0 - d)
			if f > 0.5:
				p.light(x, y, C[5], 0.18 * f)
			X += 1.0
		Y += 1.0
	# a few glints sit on the far shore
	for i in 7:
		var a := PI * (1.12 + 0.76 * ((i + 0.5) / 7.0))
		var x := cos(a) * RX * 0.96
		var y := cy + sin(a) * RY * 0.96
		var g := sin(ph * TAU * 2.0 + i * 2.4)
		if g > 0.2:
			p.px(x, y, C[6] if g > 0.8 else C[4])
	# the falls mirrored in the water, broken by the chop
	p.shade(-W - 3.0, 3.0, W + 3.0, 10.0, func(x: float, y: float, out):
		var n := Px.tileNoise(x * 0.9, (y - 3.0) * 0.35 + ph * 6.0, 0.0, 6.0, S + 6.0)
		var k := 1.0 - (y - 3.0) / 7.0
		if absf(x) > W + 2.0 - (y - 3.0) * 0.4 or n < 0.25 + (1.0 - k) * 0.4:
			return
		out.c = C[6] if (n > 0.6 and k > 0.6) else C[5])


# the foot: a churning white band, billows rolling out of it, spray thrown clear landing with rings
static func foam(p: Px.Painter, C: Array, t: float, ph: float, W: float, S: float) -> void:
	var R := W + 10.0
	p.shade(-R, -13.0, R, 3.0, func(x: float, y: float, out):
		var ax := absf(x)
		var lump := Px.tileNoise(x * 0.22, ph * 6.0, 0.0, 6.0, S + 7.0) * 3.0 + Px.tileNoise(x * 0.55 + 9.0, ph * 12.0, 0.0, 12.0, S + 8.0) * 1.5
		var top := -8.0 + lump + pow(ax / R, 2.0) * 7.0
		if ax > R - maxf(0.0, -y - 1.0) * 0.6 or y < top:
			return
		# the churn in lumps: each boil lit on top, shadowed under, darker where it meets the pool
		var n := Px.tileNoise(x * 0.5, (y - top) * 0.5 - ph * 10.0, 0.0, 10.0, S + 9.0)
		var boil := Px.tileNoise(x * 0.42 + 3.0, y * 0.42 - ph * 8.0, 0.0, 8.0, S + 12.0)
		var u := y - top
		if y > 1.0:
			out.c = C[5] if n > 0.0 else C[4]
		elif u < 1.2:
			out.c = WHITE
		elif boil < -0.3:
			out.c = C[4] if u > 4.0 else C[5]
		elif boil < -0.05:
			out.c = C[6]
		else:
			out.c = WHITE if n > -0.2 else C[6])
	Px.cycle(t, D, 30, S + 10.0, 0.7, func(age: float, life: float, r: Px.Rng):
		var k := age / life
		var side := r.sign()
		var x0 := r.range(-W, W) * 0.9
		var sp := r.range(2.0, 8.0)
		var up := r.range(2.0, 8.0)
		var x := x0 + side * Px.Ease.outCubic(k) * sp
		var y := -r.range(2.0, 5.0) - Px.Ease.outCubic(k) * up
		var rad := r.range(1.4, 3.0) * pow(sin(PI * k), 0.7)
		if rad > 0.6:
			Lib.billow(p, x, y, rad, C))
	# spray: beads thrown clear of the churn, landing in the pool with a ring
	Px.cycle(t, D, 18, S + 11.0, 1.0, func(age: float, life: float, r: Px.Rng):
		var side := r.sign()
		var x0 := side * r.range(2.0, W + 4.0)
		var vx := side * r.range(12.0, 60.0)
		var vy := -r.range(70.0, 150.0)
		var z := r.range(-3.0, 9.0)
		var s := 2.0 if r.next() < 0.3 else 1.0
		var land := z * SY
		var tl := (-vy + sqrt(vy * vy + 2.0 * G * (land + 5.0))) / G
		if age < tl:
			Lib.bead(p, x0 + vx * age, -5.0 + vy * age + 0.5 * G * age * age, vx, vy + G * age, s, C)
		elif age < tl + 0.35:
			Lib.ring(p, x0 + vx * tl, land, 1.0 + (age - tl) * 12.0, SY, 1.0 - (age - tl) / 0.35, C, {"n": 1.0}))


# mist: soft puffs rolled out of the churn that drift sideways along the pool, swell and thin, with a cool light
static func mist(p: Px.Painter, C: Array, t: float, S: float, n: float, seed: float) -> void:
	Px.cycle(t, D, n, S + seed, func(g: Px.Rng): return g.range(1.8, 2.8), func(age: float, life: float, r: Px.Rng):
		var k := age / life
		var side := r.sign()
		var drift := Px.Ease.outCubic(k)
		var x := side * (r.range(3.0, 12.0) + drift * r.range(24.0, 48.0))
		var y := -r.range(2.0, 7.0) - k * r.range(3.0, 12.0)
		var rad := r.range(4.0, 6.0) + k * r.range(5.0, 9.0)
		var a := r.range(0.2, 0.3) * minf(1.0, k / 0.12) * pow(1.0 - k, 1.7)
		p.disc(x, y, rad, C[6], func(d: float): return a * (1.0 - d * d))
		if a > 0.05:
			p.glow(x, y, rad * 1.2, C[4], 0.35 * a))


static func drawBack(p: Px.Painter, t: float, o: Dictionary) -> void:
	var C := Px.fit(o.palette, 8)
	var ph := t / D
	var W: float = o.width
	pool(p, C, ph, W, o.seed)
	for i in 3:
		var f := fmod(ph + i / 3.0, 1.0)
		Lib.ring(p, 0.0, 1.0, W + 6.0 + f * 38.0, SY, 0.95 * pow(1.0 - f, 1.5), C, {"n": 1.0, "half": -1.0, "seed": i + 1})
	mist(p, C, t, o.seed, 7.0, 20.0)


static func draw(p: Px.Painter, t: float, o: Dictionary) -> void:
	var C := Px.fit(o.palette, 8)
	var ph := t / D
	var H: float = o.height
	var W: float = o.width
	var S: float = o.seed
	var T := ph * TAU
	for i in 3:
		var f := fmod(ph + i / 3.0, 1.0)
		Lib.ring(p, 0.0, 1.0, W + 6.0 + f * 38.0, SY, 0.95 * pow(1.0 - f, 1.5), C, {"n": 1.0, "half": 1.0, "seed": i + 1, "glint": 1.0 - f * 2.5 if f < 0.4 else 0.0})
	river(p, C, ph, H, W, S)
	if o.ledge:
		outcrop(p, C, ph, H, W, S)
	sheet(p, C, ph, H, W, S)
	curl(p, C, ph, H, W, S)
	foam(p, C, t, ph, W, S)
	mist(p, C, t, S, 5.0, 21.0)
	# glints wink on the falling water and in the spray
	Px.cycle(t, D, 12, S + 50.0, func(g: Px.Rng): return g.range(0.2, 0.4), func(age: float, life: float, r: Px.Rng):
		var k := sin((PI * age) / life)
		var low := r.next() < 0.45
		var d := H - r.range(4.0, 16.0) if low else r.range(12.0, H - 16.0)
		var x := r.range(-W - 10.0, W + 10.0) if low else r.range(-0.8, 0.8) * halfW(W, d, H)
		var y := -H + d - (age / life) * (6.0 if low else -10.0)
		p.px(x, y, WHITE)
		if k > 0.55:
			for dd: Array in [[1, 0], [-1, 0], [0, 1], [0, -1]]:
				p.px(x + dd[0], y + dd[1], C[6])
		if k > 0.85 and r.next() < 0.5:
			for dd: Array in [[2, 0], [-2, 0], [0, 2], [0, -2]]:
				p.px(x + dd[0], y + dd[1], C[5])
		p.glow(x, y, 5.0, C[5], 0.35 * k))
	# fine spray hangs in the air off the foot, drifting up and out
	Px.cycle(t, D, 34, S + 51.0, func(g: Px.Rng): return g.range(0.9, 1.6), func(age: float, life: float, r: Px.Rng):
		var k := age / life
		var side := r.sign()
		var x := side * (r.range(0.0, W + 6.0) + k * r.range(6.0, 22.0)) + sin(age * 5.0 + r.range(0.0, TAU)) * 1.2
		var y := -r.range(3.0, 10.0) - k * r.range(10.0, 34.0)
		if k > 0.7 and r.next() < (k - 0.7) * 3.3:
			return
		p.px(x, y, WHITE if (k < 0.4 and r.next() < 0.5) else C[6]))
	# light: down the sheet, a pool of it where the water lands, on the water around
	p.glowLine(0.0, -H + 6.0, 0.0, -8.0, 26.0, C[4], 0.12)
	p.glow(0.0, -5.0, 40.0, C[5], 0.32 + 0.05 * sin(T * 2.0))
	p.glow(0.0, 4.0, 50.0, C[3], 0.14)
