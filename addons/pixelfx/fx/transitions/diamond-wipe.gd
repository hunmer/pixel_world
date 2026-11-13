# The faceted shading (a lit ridge, a bright face toward the light, a dark one away, a bright rim) follows
# Sprite Fusion's open-source ice crystals (https://www.spritefusion.com/pixel-art-vfx/ice), MIT License,
# Copyright (c) 2026 Hugo Duprez.
# port-of: src/fx/transitions/diamond-wipe.js@518680ebe5412e8684915bf2a5c7314ddc37a59e
extends RefCounted

const Px := preload("../../core/px.gd")
const Lib := preload("_lib.gd")
const WHITE := Px.WHITE
const W := Lib.W
const H := Lib.H

static var meta := Lib.screenMeta({
	"name": "Diamond wipe",
	"desc": "A wave of faceted diamonds swells across the screen, rims bright and ridges lit, cooling to black as they lock; then they rise as gems again and shrink away with glints.",
	"tags": ["diamond", "lattice", "geometric", "wipe"],
	"duration": 2.0,
	"options": {"palette": Px.PAL.arcane, "seed": 1},
})

const S := 32.0
const HD := S / 2.0 + 1.0
const GROW := 0.24
const IN0 := 0.04
const IN1 := 0.66
const OUT0 := 1.05
const OUT1 := 1.56

# the lattice: rows of diamonds S apart, every other row shifted half a step, so they tile when full
static var cache := {}


static func lattice(seed: float) -> Array:
	if cache.has(seed):
		return cache[seed]
	var out := []
	for j in range(-1, int(ceilf(H / (S / 2.0))) + 2):
		for i in range(-1, int(ceilf(W / S)) + 2):
			var cx := i * S + (S / 2.0 if j & 1 else 0.0)
			var cy := (j * S) / 2.0
			if cx + HD < 0.0 or cy + HD < 0.0 or cx - HD > W or cy - HD > H:
				continue
			# the wave runs left to right on a slant, each diamond a little early or late
			var u := Px.clamp((cx + 0.45 * cy) / (W + 0.45 * H))
			var jr := Px.rand(i, j, seed)
			out.append({"cx": cx, "cy": cy, "tin": IN0 + (IN1 - IN0) * Px.clamp(u + (jr - 0.5) * 0.08), "tout": OUT0 + (OUT1 - OUT0) * Px.clamp(u + (Px.rand(i, j, seed + 1.0) - 0.5) * 0.08), "glint": jr < 0.3, "spin": Px.rand(i, j, seed + 2.0) * 3.0})
	cache[seed] = out
	return out


static func draw(p0: Px.Painter, t: float, o: Dictionary) -> void:
	var C := Px.fit(o.palette, 8)
	var ink := Px.hex(o.color)
	var p := Lib.clipTo(p0)
	var L := lattice(o.seed)
	var glints := []
	# facets, toward the light first: top left, top right, bottom left, bottom right; and how each cools
	# (faces stay in the shadow end of the ramp: the rims and ridges carry the light)
	var FACE := [[C[2], C[1], C[0]], [C[1], C[0], C[0]], [C[1], C[0], C[0]], [C[0], C[0], ink]]
	for d: Dictionary in L:
		var ki: float = (t - d.tin) / GROW
		var ko: float = (t - d.tout) / GROW
		# the last glint as it winks out
		if d.glint and ko > 0.7 and ko < 1.5:
			glints.append([d, (ko - 0.7) / 0.8, 0.0])
		if ki <= 0.0 or ko >= 1.0:
			continue
		# its size: swelling in with an overshoot; out, a breath bigger and then shrinking to nothing
		var hd := HD * (1.0 - Px.Ease.inBack(ko, 2.0) if ko > 0.0 else Px.Ease.outBack(minf(1.0, ki), 2.2))
		# its heat: bright while it swells, cooling once it's locked in; lighting up again as it goes
		var heat := Px.smooth(0.0, 0.35, ko) if ko > 0.0 else 1.0 - Px.smooth(0.45, 1.25, ki)
		if hd < 0.5:
			continue
		var settled := heat <= 0.0
		var cx: float = d.cx
		var cy: float = d.cy
		var y0 := maxf(0.0, floorf(cy - hd))
		var y1 := minf(H - 1.0, ceilf(cy + hd))
		for y in range(int(y0), int(y1) + 1):
			var dy := y + 0.5 - cy
			var w := hd - absf(dy)
			if w <= 0.0:
				continue
			var x0 := maxf(0.0, ceilf(cx - w - 0.5))
			var x1 := minf(W - 1.0, floorf(cx + w - 0.5))
			if x1 < x0:
				continue
			if settled:
				Lib.rect(p0, x0, y, x1 - x0 + 1.0, 1.0, ink)
				continue
			var st := 0 if heat > 0.66 else (1 if heat > 0.33 else 2)
			for x in range(int(x0), int(x1) + 1):
				var dx := x + 0.5 - cx
				var e := hd - absf(dx) - absf(dy)  # e: px in from the rim
				var q := (0 if dy < 0.0 else 2) + (0 if dx < 0.0 else 1)
				var vr := dx > -1.0 and dx <= 0.0  # the centre column and row
				var hr := dy > -1.0 and dy <= 0.0
				var c: Variant
				if e < 1.0:
					# the rim, lit from the top left: white there, cooling round to the far side
					var r: Variant = [WHITE if heat > 0.5 else C[6], C[6] if heat > 0.5 else C[5], C[5] if heat > 0.5 else C[4], C[4] if heat > 0.5 else C[3]][q]
					c = r if heat > 0.15 else ink
					if heat > 0.15:
						p0.light(x, y, C[5], 0.4 * heat * (1.0 if q == 0 else 0.6))
				elif e < 2.0 and q == 0 and heat > 0.4:
					c = C[5]
				elif (vr or hr) and heat > 0.3:
					# ridges, with a white tip at the top point and a sheen running down them
					var tip := vr and dy < -hd + 4.0
					var sheen := absf(fmod(fmod(x + y - t * 260.0, 90.0) + 90.0, 90.0) - 45.0) < 3.0
					c = WHITE if tip or (sheen and heat > 0.5) else ((C[6] if heat > 0.6 else C[5]) if vr and dy < 0.0 else (C[3] if heat > 0.6 else C[2]))
				else:
					c = FACE[q][st] if heat > 0.15 else ink
				p0.px(x, y, c)
		if not settled:
			p.glow(cx, cy, hd + 6.0, C[4], 0.22 * heat)
		# a glint on its top point as it locks in
		if ki > 0.6 and ki < 1.8 and d.glint:
			glints.append([d, (ki - 0.6) / 1.2, hd])
	for gl: Array in glints:
		var d: Dictionary = gl[0]
		var u: float = gl[1]
		var hd: float = gl[2]
		if u <= 0.0 or u >= 1.0:
			continue
		var y: float = d.cy - hd if hd else d.cy
		Lib.glint(p, d.cx, y, 9.0 * pow(sin(PI * u), 0.7), d.spin + u * 1.5, C[6], C[5])
