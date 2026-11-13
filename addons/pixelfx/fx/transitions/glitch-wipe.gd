# The specks of white, cyan and magenta a body breaks into follow Sprite Fusion's open-source blink
# (https://www.spritefusion.com/pixel-art-vfx/movement), MIT License, Copyright (c) 2026 Hugo Duprez.
# port-of: src/fx/transitions/glitch-wipe.js@f6cfb7df143c02e540d169b564b9bbb0dbd9964d
extends RefCounted

const Px := preload("../../core/px.gd")
const Lib := preload("_lib.gd")
const WHITE := Px.WHITE
const W := Lib.W
const H := Lib.H

static var meta := Lib.screenMeta({
	"name": "Glitch wipe",
	"desc": "Torn bands of black stutter across the screen, freezing and jerking back, their ragged edges split into magenta and cyan ghosts spitting data slivers; then they tear on through.",
	"tags": ["glitch", "digital", "rgb", "bands", "wipe"],
	"duration": 1.8,
	"options": {"palette": Px.PAL.cyber, "split": "#ff2d6f", "seed": 1},
})

const TICK := 1.0 / 18.0
const IN0 := 0.03
const IN1 := 0.78
const OUT0 := 0.98
const OUT1 := 1.66

# the bands: torn strips of different thickness. Neighbours move together in chunks (their timing follows a
# smooth noise down the screen), mostly left to right, now and then one from the other side
static var cache := {}


static func bands(seed: float) -> Array:
	if cache.has(seed):
		return cache[seed]
	var out := []
	var y := 0
	var i := 0
	while y < H:
		var r := Px.rand(i, seed)
		var h := mini(H - y, 5 + floori(Px.rand(i, seed + 1.0) * 6.0) if r < 0.4 else (10 + floori(Px.rand(i, seed + 1.0) * 10.0) if r < 0.85 else 20 + floori(Px.rand(i, seed + 1.0) * 12.0)))
		var a := Px.clamp(0.5 + 0.55 * Px.noise(y / 40.0, seed + 9.0) + (Px.rand(i, seed + 2.0) - 0.5) * 0.25)
		var b := Px.clamp(0.5 + 0.55 * Px.noise(y / 40.0, seed + 19.0) + (Px.rand(i, seed + 3.0) - 0.5) * 0.25)
		var span := 0.32 + Px.rand(i, seed + 6.0) * 0.12
		out.append({"i": i, "y": y, "h": h, "dir": 1 if Px.rand(i, seed + 4.0) < 0.82 else -1, "off": Px.rand(i, seed + 5.0), "t0": IN0 + a * (IN1 - IN0 - span), "t1": IN0 + a * (IN1 - IN0 - span) + span, "o0": OUT0 + b * (OUT1 - OUT0 - span), "o1": OUT0 + b * (OUT1 - OUT0 - span) + span})
		y += h
		i += 1
	cache[seed] = out
	return out


# how far a band has torn at t: it moves only on ticks, by uneven jumps, sometimes freezing, sometimes
# jerking back a little, but it always starts at 0 and ends at 1
static func tear(b: Dictionary, t: float, t0: float, t1: float, salt: int) -> float:
	if t <= t0:
		return 0.0
	if t >= t1:
		return 1.0
	var n := floori((t + b.off * TICK) / TICK)
	while n > 0 and Px.rand(n, b.i, salt) < 0.22:
		n -= 1  # frozen ticks hold the last position
	var tq: float = n * TICK - b.off * TICK
	var u := Px.clamp((tq - t0) / (t1 - t0))
	return Px.clamp(Px.Ease.inOutQuad(u) + (Px.rand(n, b.i, salt + 1) - 0.6) * 0.12 * sin(PI * u))


static func draw(p0: Px.Painter, t: float, o: Dictionary) -> void:
	var C := Px.fit(o.palette, 8)
	var ink := Px.hex(o.color)
	var RED := Px.hex(o.split)
	var p := Lib.clipTo(p0)
	var B := bands(o.seed)
	var fr := floori(t / TICK)
	var out := t >= OUT0
	for b: Dictionary in B:
		var bi: int = b.i
		var by: int = b.y
		var bh_: int = b.h
		var k := tear(b, t, b.o0, b.o1, 7) if out else tear(b, t, b.t0, b.t1, 3)
		if (not out and k <= 0.0) or (out and k >= 1.0):
			continue
		var moving := k > 0.0 and k < 1.0
		var slip := Px.round((Px.rand(fr, bi, 12) - 0.5) * 18.0) if moving and Px.rand(fr, bi, 11) < 0.12 else 0.0
		# the edge advances along +fwd; in, the black is behind it; out, the black is ahead of it
		var fwd: int = b.dir
		var e := (k * W if b.dir > 0 else W - k * W) + slip
		for y in range(by, by + bh_):
			# a ragged edge: each row torn a little ahead or behind, re-torn every tick
			var jag := Px.round((Px.rand(fr, y, 14) - 0.5) * 6.0 + (Px.rand(fr >> 1, bi, 15) - 0.5) * 6.0) if moving else 0.0
			var ex := Px.clamp(Px.round(e + jag), 0.0, W)
			var behind := (fwd > 0) != out  # is the black on the low-x side of the edge?
			if behind:
				if ex > 0.0:
					Lib.rect(p0, 0.0, y, ex, 1.0, ink)
			else:
				if ex < W:
					Lib.rect(p0, ex, y, W - ex, 1.0, ink)
			if not moving:
				continue
			# the torn edge: a white line, a magenta ghost on the open side and a cyan ghost in the black
			var e1 := ex - 1.0 if behind else ex
			var side := 1 if behind else -1
			var sp := 2 + ((bi + fr) % 3)
			p.px(e1, y, WHITE)
			p.px(e1 + side * sp, y, RED)
			p.px(e1 + side * (sp + 1), y, RED)
			p.px(e1 - side * (sp + 1), y, C[5])
			p.px(e1 - side * (sp + 2), y, C[4])
			p.light(e1, y, WHITE, 0.45)
			p.light(e1 + side * (sp + 1), y, RED, 0.5)
			p.light(e1 + side * (sp + 3), y, RED, 0.22)
			p.light(e1 - side * (sp + 1), y, C[5], 0.45)
			p.light(e1 - side * (sp + 3), y, C[5], 0.22)
		if not moving:
			continue
		var ex := Px.clamp(Px.round(e), 0.0, W)
		var open := 1 if ((fwd > 0) != out) else -1
		# the edge glows, and a cloud of specks crackles round it, thickest close in
		p.glow(ex, by + bh_ / 2.0, bh_ * 0.7 + 7.0, RED if (bi & 1) else C[5], 0.28)
		for s in bh_:
			if Px.rand(fr, bi, 100 + s) > 0.55:
				continue
			var x := ex + open * Px.round(Px.rand(fr, bi, 200 + s) ** 2.0 * 22.0 - 4.0)
			var y := by + floorf(Px.rand(fr, bi, 300 + s) * bh_)
			p.px(x, y, [WHITE, C[6], C[5], RED][floori(Px.rand(fr, bi, 400 + s) * 4.0)])
		# data slivers spit off the edge: dashes of light out over the picture and glitches back in the black
		for s in 4:
			if Px.rand(fr, bi, 20 + s) > 0.5:
				continue
			var len_ := 2.0 + floorf(Px.rand(fr, bi, 30 + s) ** 2.0 * 60.0)
			var ahead := Px.rand(fr, bi, 40 + s) < 0.6
			var d := floorf(Px.rand(fr, bi, 50 + s) ** 1.5 * 70.0) + 4.0
			var y := by + floorf(Px.rand(fr, bi, 60 + s) * bh_)
			var x := ((ex + d if open > 0 else ex - d - len_) if ahead else (ex - d - len_ if open > 0 else ex + d))
			var c: int = [WHITE, C[6], C[5], RED][floori(Px.rand(fr, bi, 70 + s) * 4.0)]
			p.rect(x, y, len_, 1.0, c)
			var q := 0.0
			while q < len_:
				p.light(x + q, y, c, 0.35)
				q += 3.0
		# a corrupted block or two: the outline of a broken tile near the edge
		if bh_ >= 8 and Px.rand(fr, bi, 80) < 0.35:
			var bw := 6.0 + floorf(Px.rand(fr, bi, 81) * 10.0)
			var bh := 3.0 + floorf(Px.rand(fr, bi, 82) * mini(6, bh_ - 3))
			var x := ex + open * floorf(Px.rand(fr, bi, 83) * 24.0 - 4.0) - (bw if open < 0 else 0.0)
			var y := by + floorf(Px.rand(fr, bi, 84) * (bh_ - bh))
			var c: int = C[5] if Px.rand(fr, bi, 85) < 0.5 else RED
			p.rect(x, y, bw, 1.0, c)
			p.rect(x, y + bh - 1.0, bw, 1.0, c)
			p.rect(x, y, 1.0, bh, c)
			p.rect(x + bw - 1.0, y, 1.0, bh, c)
			var q := 0.0
			while q < bw:
				p.light(x + q, y, c, 0.25)
				q += 2.0
	# while it's all black, the signal still spits now and then
	if t > IN1 and t < OUT0 + 0.05:
		for s in 3:
			if Px.rand(fr, s, 90) > 0.4:
				continue
			var y := floorf(Px.rand(fr, s, 91) * H)
			var x := floorf(Px.rand(fr, s, 92) * W)
			var len_ := 3.0 + floorf(Px.rand(fr, s, 93) ** 2.0 * 40.0)
			p.rect(x, y, len_, 1.0, C[4] if s == 0 else (C[3] if s == 1 else RED))
