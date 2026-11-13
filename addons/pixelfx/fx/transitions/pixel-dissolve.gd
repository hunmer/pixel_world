# The glints and the twinkling pixel dust follow Sprite Fusion's open-source sparkle
# (https://www.spritefusion.com/pixel-art-vfx/sparkle), MIT License, Copyright (c) 2026 Hugo Duprez.
# port-of: src/fx/transitions/pixel-dissolve.js@63ce05499f0ccf8561092f03dcae9f03189ba57f
extends RefCounted

const Px := preload("../../core/px.gd")
const Lib := preload("_lib.gd")
const WHITE := Px.WHITE
const W := Lib.W
const H := Lib.H

static var meta := Lib.screenMeta({
	"name": "Pixel dissolve",
	"desc": "Clumps of blocks wink in, each drawn in a white outline that fills black and cools, with glints; then they wink out, outlines collapsing, the last small ones sparkling away.",
	"tags": ["dissolve", "pixel", "blocks", "glint"],
	"duration": 2.2,
	"options": {"palette": Px.PAL.neon, "seed": 1},
})

const P := 0.17
const IN0 := 0.04
const IN1 := 0.8
const OUT0 := 1.12
const OUT1 := 1.85
const CELL := 20.0
const NB := [[1, 0], [-1, 0], [0, 1], [0, -1]]
const PLUS := [[0, 0], [1, 0], [-1, 0], [0, 1], [0, -1]]

# the blocks: 20 px cells, some whole, some in quarters, some in sixteenths. Each winks in and out at its own
# time read off a clumpy field, so they gather in growing patches: small ones scatter first, big ones fill in
static var cache := {}


static func layout(seed: float) -> Array:
	if cache.has(seed):
		return cache[seed]
	var blocks := []
	var cy := 0
	while cy < H / CELL:
		var cx := 0
		while cx < W / CELL:
			var h := Px.rand(cx, cy, seed)
			var n := 1 if h < 0.32 else (2 if h < 0.74 else 4)
			var s := CELL / n
			for j in n:
				for i in n:
					blocks.append({"x": cx * CELL + i * s, "y": cy * CELL + j * s, "s": s})
			cx += 1
		cy += 1
	var rank := func(key: Callable) -> PackedFloat32Array:
		var v: Array = blocks.map(key)
		var out := PackedFloat32Array()
		out.resize(v.size())
		var idx: Array = Px.sort(Px.arr(v.size(), func(i): return i), func(a, b): return v[a] - v[b])
		for k in idx.size():
			out[idx[k]] = k / float(v.size() - 1)
		return out
	var at := func(b: Dictionary, sd: float) -> float: return Px.fbm((b.x + b.s / 2.0) / 64.0, (b.y + b.s / 2.0) / 64.0, sd, 3)
	var uin: PackedFloat32Array = rank.call(func(b): return at.call(b, seed) + 0.22 * Px.rand(b.x, b.y, seed + 1.0) + (0.12 if b.s == 20.0 else (-0.08 if b.s == 5.0 else 0.0)))
	var uout: PackedFloat32Array = rank.call(func(b): return at.call(b, seed + 7.0) + 0.22 * Px.rand(b.x, b.y, seed + 2.0) + (-0.14 if b.s == 20.0 else (0.1 if b.s == 5.0 else 0.0)))
	for i in blocks.size():
		var b: Dictionary = blocks[i]
		b.tin = IN0 + uin[i] * (IN1 - IN0)
		b.tout = OUT0 + uout[i] * (OUT1 - OUT0)
		b.glint = Px.rand(b.x, b.y, seed + 3.0) < (0.32 if b.s >= 10.0 else 0.1)
		b.gx = b.x + (0.0 if Px.rand(b.x, b.y, seed + 4.0) < 0.5 else b.s)
		b.gy = b.y + (0.0 if Px.rand(b.x, b.y, seed + 5.0) < 0.5 else b.s)
		b.spin = (Px.rand(b.x, b.y, seed + 6.0) - 0.5) * 3.0
		# now and then a big block throws a hero glint
		b.L = 9.0 + 6.0 * Px.rand(b.x, b.y, seed + 9.0) if b.s == 20.0 and Px.rand(b.x, b.y, seed + 8.0) < 0.45 else 2.5 + b.s * 0.32
	cache[seed] = blocks
	return blocks


# a square block, filled, with a 1 px rim
# a mote of pixel dust: a lone pixel, or now and then a little cross
static func mote(p: Px.Painter, x: float, y: float, c: int, cross: bool) -> void:
	p.px(x, y, c)
	if cross:
		for dd in NB:
			p.px(x + dd[0], y + dd[1], c)


static func square(p: Px.Painter, x: float, y: float, s: float, fill: Variant, rim: Variant = 0) -> void:
	var X := Px.round(x)
	var Y := Px.round(y)
	var S := maxf(1.0, Px.round(s))
	if fill:
		Lib.rect(p, X, Y, S, S, fill)
	if rim and S > 2.0:
		Lib.rect(p, X, Y, S, 1.0, rim)
		Lib.rect(p, X, Y + S - 1.0, S, 1.0, rim)
		Lib.rect(p, X, Y, 1.0, S, rim)
		Lib.rect(p, X + S - 1.0, Y, 1.0, S, rim)


static func draw(p0: Px.Painter, t: float, o: Dictionary) -> void:
	var C := Px.fit(o.palette, 8)
	var ink := Px.hex(o.color)
	var p := Lib.clipTo(p0)
	var blocks := layout(o.seed)
	var glints := []
	var frame := floorf(t * 15.0)
	for n in blocks.size():
		var b: Dictionary = blocks[n]
		var ki: float = (t - b.tin) / P
		var ko: float = (t - b.tout) / P
		var x: float = b.x
		var y: float = b.y
		var s: float = b.s
		var cx := x + s / 2.0
		var cy := y + s / 2.0
		if ki < 0.0 or ko >= 1.6:
			continue
		if ko < 0.0:
			if ki >= 1.0:
				square(p0, x, y, s, ink)
			else:
				# winking in: a white outline swells to the block, it fills with black, its rim cools down the ramp
				var g := 0.35 + 0.65 * Px.Ease.outBack(ki / 0.35) if ki < 0.35 else 1.0
				var h := s * g
				var rim: int = WHITE if ki < 0.45 else (C[6] if ki < 0.6 else (C[5] if ki < 0.75 else (C[4] if ki < 0.9 else C[3])))
				square(p, cx - h / 2.0, cy - h / 2.0, h, ink if ki > 0.2 else 0, rim)
				if ki < 0.3 and s >= 10.0:
					for dd in PLUS:
						p.px(cx - 0.5 + dd[0], cy - 0.5 + dd[1], C[6] if (dd[0] or dd[1]) else WHITE)
				p.glow(cx, cy, s * 0.8 + 4.0, C[5], 0.45 * (1.0 - ki))
			if b.glint and ki > 0.15 and ki < 1.6:
				glints.append([b, (ki - 0.15) / 1.45, 1.0])
			# pixel dust flickers round the fresh block
			if ki < 1.4 and Px.rand(frame, n, 9) < 0.35:
				mote(p, x + Px.rand(frame, n, 10) * (s + 6.0) - 3.0, y + Px.rand(frame, n, 11) * (s + 6.0) - 3.0, WHITE if Px.rand(frame, n, 12) < 0.5 else C[6], Px.rand(frame, n, 17) < 0.25)
		else:
			if ko < 0.35:
				# winking out: its rim lights up...
				var q := ko / 0.35
				square(p0, x, y, s, ink, C[4] if q < 0.4 else (C[5] if q < 0.75 else C[6]))
				p.glow(cx, cy, s * 0.8 + 3.0, C[4], 0.35 * q)
			elif ko < 0.75:
				# ...the black drops away and the white outline collapses into its heart
				var q := (ko - 0.35) / 0.4
				var h := s * (1.0 - Px.Ease.inQuad(q) * 0.85)
				square(p, cx - h / 2.0, cy - h / 2.0, h, 0, WHITE if q < 0.5 else C[6])
				p.glow(cx, cy, s * 0.8 + 4.0, C[5], 0.45 * (1.0 - q * 0.5))
			elif ko < 1.0:
				var q := (ko - 0.75) / 0.25
				for dd in PLUS:
					if not (dd[0] or dd[1]) or q < 0.5:
						p.px(cx - 0.5 + dd[0], cy - 0.5 + dd[1], C[6] if (dd[0] or dd[1]) else WHITE)
				p.glow(cx, cy, s * 0.5 + 3.0, C[5], 0.35 * (1.0 - q))
			if b.glint and ko > 0.3:
				glints.append([b, (ko - 0.3) / 1.3, -1.0])
			if ko > 0.3 and ko < 1.5 and Px.rand(frame, n, 13) < 0.3:
				mote(p, x + Px.rand(frame, n, 14) * (s + 6.0) - 3.0, y + Px.rand(frame, n, 15) * (s + 6.0) - 3.0, WHITE if Px.rand(frame, n, 16) < 0.5 else C[6], Px.rand(frame, n, 18) < 0.25)
	# glints on top: a spinning star on a corner of the block, swelling and fading
	for gl: Array in glints:
		var b: Dictionary = gl[0]
		var u: float = gl[1]
		var dir: float = gl[2]
		if u <= 0.0 or u >= 1.0:
			continue
		var L: float = b.L * pow(sin(PI * u), 0.7)
		Lib.glint(p, b.gx, b.gy, L, b.spin * u * dir + 0.4, C[5], C[4])
		if b.L > 8.0:
			p.glow(b.gx, b.gy, 18.0 + L, C[5], 0.25 * sin(PI * u))
