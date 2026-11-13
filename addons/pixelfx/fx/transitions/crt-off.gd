# The glowing line (a white core, a pale fringe, an outer fringe while it's fresh, light along it) follows
# Sprite Fusion's open-source lightning strike (https://www.spritefusion.com/pixel-art-vfx/lightning),
# MIT License, Copyright (c) 2026 Hugo Duprez.
# port-of: src/fx/transitions/crt-off.js@7320aea552f34cb932908078583ad52d4a1a94b5
extends RefCounted

const Px := preload("../../core/px.gd")
const Lib := preload("_lib.gd")
const WHITE := Px.WHITE
const W := Lib.W
const H := Lib.H

static var meta := Lib.screenMeta({
	"name": "CRT off",
	"desc": "The picture squeezes into a white-hot glowing line, the line into a dot that lingers as a fading afterglow; then it switches back on, dot to line to picture, with a warm-up glow.",
	"tags": ["crt", "tv", "retro", "switch", "wipe"],
	"duration": 2.0,
	"options": {"palette": ["#060a14", "#0e1a33", "#1a3360", "#2a5a9a", "#4a8fd0", "#8cc4f0", "#d4ecff", "#ffffff"], "seed": 1},
})

const YC := H / 2.0
const XC := W / 2.0
# off: squeeze to a line, the line to a dot, the dot fades; on: a dot, a line, the picture
const SQ0 := 0.06
const SQ1 := 0.34
const LN1 := 0.56
const DOT1 := 0.86
const ON0 := 1.06
const ON1 := 1.16
const OPEN1 := 1.42


# the visible strip's height and the line's half-length at time t
static func shape(t: float) -> Dictionary:
	if t < SQ0:
		return {"h": float(H), "w": XC}
	if t < SQ1:
		return {"h": maxf(1.0, H * (1.0 - Px.Ease.inCubic((t - SQ0) / (SQ1 - SQ0)))), "w": XC}
	if t < LN1:
		return {"h": 1.0, "w": XC * (1.0 - Px.Ease.inQuad((t - SQ1) / (LN1 - SQ1)))}
	if t < ON0:
		return {"h": 0.0, "w": 0.0}
	if t < ON1:
		return {"h": 1.0, "w": XC * Px.Ease.outExpo((t - ON0) / (ON1 - ON0))}
	return {"h": maxf(1.0, H * Px.Ease.outCubic(Px.clamp((t - ON1) / (OPEN1 - ON1)))), "w": XC}


static func draw(p0: Px.Painter, t: float, o: Dictionary) -> void:
	var C := Px.fit(o.palette, 8)
	var ink := Px.hex(o.color)
	var p := Lib.clipTo(p0)
	var sh := shape(t)
	var h: float = sh.h
	var w: float = sh.w
	var fl := 0.85 + 0.15 * Px.rand(floorf(t * 30.0), 7, o.seed)
	if t >= OPEN1 + 0.02 and t < OPEN1 + 0.6:
		# switched on: a warm-up glow over the picture, a bright refresh band rolling down it once, scanlines
		var u := (t - OPEN1) / 0.6
		var band := -20.0 + u * (H + 40.0)
		for y in H:
			var k := 0.22 * (1.0 - u) ** 2 + 0.3 * maxf(0.0, 1.0 - absf(y - band) / 10.0) ** 2 * (1.0 - u) + (0.05 * (1.0 - u) if y & 1 else 0.0)
			if k > 0.01:
				for x in W:
					p0.light(x, y, C[5], k)
		return
	if h >= H:
		return
	var top := Px.round(YC - h / 2.0)
	var bot := Px.round(YC + h / 2.0)
	# the dark closing in from above and below
	if top > 0.0:
		Lib.rect(p0, 0.0, 0.0, W, top, ink)
	if bot < H:
		Lib.rect(p0, 0.0, bot, W, H - bot, ink)
	if h > 2.0:
		# the squeezed picture: brighter as it narrows, with scanlines, its edges glowing where the dark meets it
		var sq := 1.0 - h / H
		for y in range(int(top), int(bot)):
			var e := minf(y - top, bot - 1.0 - y)
			var k := 0.55 * sq * sq + (0.08 * sq if y & 1 else 0.0) + 0.35 * maxf(0.0, 1.0 - e / 6.0) ** 2
			for x in W:
				p0.light(x, y, C[5], k * fl)
		for y in [top - 1.0, bot]:
			if y >= 0.0 and y < H:
				Lib.rect(p0, 0.0, y, W, 1.0, C[6] if sq > 0.6 else C[5])
		return
	# the line (and the dot it shrinks to): white-hot core, a pale fringe, an outer fringe while it's fresh, light
	var dotPhase := t >= LN1 and t < ON0
	var x0 := floorf(XC - w)
	var x1 := ceilf(XC + w)
	var fresh := t < SQ1 + 0.08 or (t > ON0 and t < ON1 + 0.04)
	if h > 0.0 and w >= 1.0:
		var fr := floorf(t * 30.0)
		for x in range(int(maxf(0.0, x0)), int(minf(W, x1))):
			# it hums: the line wavers a pixel here and there, and crackles with flecks of static
			var u := absf(x + 0.5 - XC) / w
			var y := YC + Px.round(Px.noise(x / 23.0 + t * 9.0, o.seed) * (0.7 + 0.5 * u))  # 0 middle .. 1 ends
			p0.px(x, y, WHITE if u < 0.85 else C[6])
			if u < 0.92:
				p0.px(x, y - 1.0, C[6])
				p0.px(x, y + 1.0, C[6] if u < 0.6 else C[5])
			if fresh and u < 0.8:
				p0.dot(x, y - 2.0, C[4], 0.5)
				p0.dot(x, y + 2.0, C[4], 0.5)
			if Px.rand(x, fr, o.seed + 3.0) < 0.06:
				p.px(x, y + (-1.0 if Px.rand(x, fr, o.seed + 4.0) < 0.5 else 1.0) * (2.0 + floorf(Px.rand(x, fr, o.seed + 5.0) * 4.0)), WHITE if Px.rand(x, fr, 6) < 0.5 else C[5])
			p0.light(x, y, C[6], 0.5 * fl * (1.0 - u * 0.6))
		var x := x0
		while x <= x1:
			p.glow(x, YC, 10.0, C[5], 0.35 * fl)
			x += 9.0
		p.glow(XC, YC, minf(70.0, 16.0 + w * 0.4), C[5], 0.4 * fl)
	# the dot: a glint that holds a moment, then an afterglow cooling to nothing
	if dotPhase:
		var u := (t - LN1) / (DOT1 - LN1)
		if u < 0.35:
			Lib.glint(p, XC, YC, 10.0 * (1.0 - u / 0.35) + 3.0, 0.2 + u * 2.0, C[6], C[5])
		if u < 1.0:
			p.px(XC, YC, WHITE if u < 0.5 else (C[6] if u < 0.75 else C[4]))
			p.px(XC - 1.0, YC, C[6] if u < 0.4 else C[4])
			# the phosphor smears the dot sideways as it cools
			var sm := Px.round(9.0 * (1.0 - u))
			var k := 2.0
			while k <= sm:
				p.dot(XC - k, YC, C[4], 1.0 - k / (sm + 1.0))
				p.dot(XC + k - 1.0, YC, C[4], 1.0 - k / (sm + 1.0))
				k += 1.0
			p.glow(XC, YC, 22.0 * (1.0 - u * 0.5), C[5], 0.55 * (1.0 - u) ** 1.5)
	# switching on: a pop of light at the heart before the line runs out
	var s := t - ON0
	if s >= 0.0 and s < 0.14:
		Lib.glint(p, XC, YC, 12.0 * (1.0 - s / 0.14) + 2.0, 0.4 + s * 6.0, C[6], C[5])
		p.glow(XC, YC, 40.0, WHITE, 0.5 * (1.0 - s / 0.14))
