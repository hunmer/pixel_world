# The layered head, rim rays and trail light follow Sprite Fusion's open-source energy bolt and orb
# (https://www.spritefusion.com/pixel-art-vfx/energy), MIT License, Copyright (c) 2026 Hugo Duprez.
# port-of: src/fx/projectiles/plasma-shot.js@2e1a0f5b74cf80a7e98ae53500c644908d844edc
extends RefCounted

const Px := preload("../../core/px.gd")
const Lib := preload("_lib.gd")
const WHITE := Px.WHITE

static var meta := {
	"name": "Plasma shot",
	"desc": "A glowing plasma blob: hot knots churning in its core, a corona crackling over its skin, its tail necking into droplets that tear off, cool and wink out behind.",
	"tags": ["projectile", "plasma", "energy", "sci-fi", "directional", "loop"],
	"size": [144, 60],
	"origin": [108, 30],
	"duration": 0.8,
	"loop": true,
	"fps": 30,
	"bg": "sky",
	"options": {
		"palette": ["#061a1c", "#0b3b34", "#0f6a4a", "#18a05a", "#3fd46a", "#8cf57e", "#d6ffc4", "#ffffff"],
		"size": 6,
		"speed": 200,
		"seed": 3,
	},
}


static func draw(p: Px.Painter, t: float, o: Dictionary) -> void:
	var C := Px.fit(o.palette, 8)
	var R: float = o.size
	var V: float = o.speed
	var S: float = o.seed
	var D: float = meta.duration
	var w := (TAU * t) / D
	var fr := floorf(t * 30.0 + 1e-6)
	var left: float = -meta.origin[0] + 2.0

	# an ion streak left in the air behind it, rippling and cooling in steps
	var T0 := -R * 3.2
	var tail := func(x: float) -> float: return sin(x * 0.2 + w * 2.0) * (0.3 + ((T0 - x) / 44.0) * 1.8)
	var x := T0
	while x > T0 - 44.0:
		var u := (T0 - x) / 44.0
		var y: float = tail.call(x)
		p.dot(x, y, C[6] if u < 0.2 else (C[5] if u < 0.45 else C[4]), 1.0 if u < 0.55 else (1.0 - u) / 0.45)
		if u < 0.3:
			p.px(x, y + 1.0, C[5] if u < 0.15 else C[4])
		x -= 1.0

	# the blob as a field of balls: a body, three hot knots churning round inside it at their own speeds, a wagging
	# tail, and droplets that cling to the tail's end until the air tears them off (the skin necks as they part)
	var balls := [{"x": 0.0, "y": 0.0, "r": R, "h": 1.0, "core": 0.8}]
	for i in 3:
		var a: float = w * [2.0, -3.0, 5.0][i] + (i * TAU) / 3.0
		var d := R * (0.5 + 0.1 * sin(w * 3.0 + i * 2.0))
		balls.append({"x": cos(a) * d - 0.4, "y": sin(a) * d * 0.8, "r": R * 0.32, "h": 1.0, "core": 1.0})
	# the tail: thick and hot where it leaves the body, tapering and cooling to a point, its axis still glowing
	for i in range(1, 7):
		var bx := -R * (0.5 + i * 0.42)
		var wag := sin(w * 2.0 - i * 0.9) * (0.3 + i * 0.28)
		var r := R * (0.62 - i * 0.08)
		balls.append({"x": bx, "y": wag, "r": r, "h": 0.96 - i * 0.05, "core": sqrt((5.2 - i * 0.65) * 0.3) / r})
	var drops := []
	Px.cycle(t, D, 11, S, func(r): return r.range(0.34, 0.5), func(age: float, life: float, r: Px.Rng) -> void:
		var k := age / life
		var pull := r.range(450.0, 800.0)
		var dx := -R * 2.9 - 0.5 * pull * age * age - r.range(0.0, 16.0) * age
		var dy := sin(w * 2.0 - 5.4 + age * 12.0) * 2.0 + r.range(-30.0, 30.0) * age * (0.4 + age)
		var rad := R * r.range(0.3, 0.48) * (1.0 - k * 0.6)
		drops.append({"x": dx, "y": dy, "r": rad, "h": 0.97 * (1.0 - k * 0.75), "core": sqrt(maxf(0.0, 1.0 - k * 1.3) * 7.0 * 0.3) / rad, "k": k}))
	var all := balls + drops
	# (all's fields copied into flat arrays for the per-pixel loop: the same numbers, far fewer lookups)
	var NB := all.size()
	var BX := PackedFloat64Array()
	var BY := PackedFloat64Array()
	var BR := PackedFloat64Array()
	var BH := PackedFloat64Array()
	var BC := PackedFloat64Array()
	for b: Dictionary in all:
		BX.append(b.x)
		BY.append(b.y)
		BR.append(b.r)
		BH.append(b.h)
		BC.append(b.core)
	# the skin comes from a compact field (so the tail tapers and droplets neck cleanly as they part); the hot
	# bands inside come only from the body and its churning knots: a deep rim, the body, a bright inner, a pale
	# core, white where the knots run hottest
	p.shade(-R * 2.6 - 60.0, -R * 2.0 - 8.0, R * 1.6, R * 2.0 + 8.0, func(px: float, py: float) -> Variant:
		var f := 0.0
		var heat := 0.0
		var hh := 0.0
		for b in NB:
			var dx := px - BX[b]
			var dy := py - BY[b]
			var d2 := dx * dx + dy * dy
			var q := d2 / (4.0 * BR[b] * BR[b])
			if q < 1.0:
				var c := ((1.0 - q) * (1.0 - q)) / 0.5625
				f += c
				heat += c * BH[b]
			if BC[b]:
				hh += (BC[b] * BC[b] * BR[b] * BR[b]) / (d2 + 0.3)
		if f < 1.0:
			return null
		var lvl := 7 if hh > 10.0 else (6 if hh > 4.6 else (5 if hh > 2.2 else (4 if f > 1.4 else 3)))
		var cap := Px.roundi(2.0 + (heat / f) * 5.4)
		return C[maxi(2, mini(lvl + 1 if (px > R * 0.3 and lvl < 5) else lvl, cap))])

	# the corona: jagged arcs leaping off the skin and back, and rays flickering round the rim, new every frame
	for j in 3:
		var g := Px.rng(fr, j, S)
		var a0 := g.range(-2.3, 2.3)
		var span := g.range(0.45, 0.9) * g.sign()
		var n := 6
		var hgt := g.range(1.5, 3.5)
		var pts := []
		for i in n + 1:
			var a := a0 + (span * i) / n
			var rr := R + 0.6 + hgt * sin((PI * i) / n) + (g.range(-0.5, 0.5) if i % n else 0.0)
			pts.append([cos(a) * rr - 0.4, sin(a) * rr * 0.92])
		p.polyline(pts, C[5] if j else C[6])
		p.px(pts[3][0], pts[3][1], WHITE)
		p.glow(pts[3][0], pts[3][1], 6.0, C[5], 0.4)
	for j in 4:
		var g := Px.rng(fr, j + 9, S)
		var a := g.range(-2.2, 2.2)
		var l := g.range(1.5, 4.0)
		var r0 := R + 1.0
		var x0 := cos(a) * r0 - 0.4
		var y0 := sin(a) * r0 * 0.92
		p.line(x0, y0, x0 + cos(a) * l, y0 + sin(a) * l, C[4] if j % 2 else C[5])
	# motes flung off the corona, streaking back
	var SP := [WHITE, C[6], C[5], C[3]]
	Lib.beat(t, D, 14, S + 5.0, func(r): return r.range(0.12, 0.3), func(age: float, life: float, r: Px.Rng) -> void:
		var a := r.range(-2.4, 2.4)
		var sp := r.range(60.0, 130.0)
		var wk := Lib.wake(cos(a) * (R + 1.0), sin(a) * (R + 1.0), cos(a) * sp, sin(a) * sp, age, V * 0.7, 4.0, 0.0)
		var sx: float = wk[0]
		var sy: float = wk[1]
		if sx > left + 4.0 and absf(sy) < 26.0:
			Lib.spark(p, sx, sy, wk[2], wk[3], 1.0 - age / life, SP, 0.4, 0.015, 6.0))

	# light: a big soft pool, a hot heart that pulses with the churn, a point on every droplet
	var pulse := 0.85 + 0.15 * sin(w * 4.0)
	p.glow(-2.0, 0.0, 34.0, C[3], 0.8 * pulse)
	p.glow(0.0, 0.0, 16.0, C[4], 0.35 * pulse)
	p.glow(1.0, 0.0, 7.0, C[6], 0.3 * pulse)
	p.glowLine(-R, 0.0, -R * 4.6, 0.0, 7.0, C[3], 0.3)
	for d: Dictionary in drops:
		if d.x < left + 4.0:
			continue
		if d.k < 0.6 and d.x < -R * 3.5:
			p.px(d.x, d.y, C[7] if d.k < 0.3 else C[6])
		p.glow(d.x, d.y, 3.0 + d.r * 2.0, C[2], 0.6 * (1.0 - d.k))
