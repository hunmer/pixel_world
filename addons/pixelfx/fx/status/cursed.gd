# The soft lit smoke puffs and the shaded, outlined skull are
# adapted from Sprite Fusion's open-source poison (https://www.spritefusion.com/pixel-art-vfx/poison),
# MIT License, Copyright (c) 2026 Hugo Duprez.
# port-of: src/fx/status/cursed.js@00358c595ae03f09fca39d379fdd13d17f6f8a1e
extends RefCounted

const Px := preload("../../core/px.gd")
const Lib := preload("_lib.gd")

static var meta := {
	"name": "Cursed",
	"desc": "Hexed: violet smoke rises off the body in winding trails, a dark stain creeps up from the feet with a glowing edge, the eyes burn, a skull glitches in overhead.",
	"tags": ["status", "curse", "hex", "dark", "debuff", "shadow", "loop"],
	"size": [64, 84],
	"origin": [32, 76],
	"duration": 2.4,
	"loop": true,
	"fps": 30,
	"bg": "ground",
	"actor": 2,
	"options": {"palette": ["#0c0612", "#1f0f2e", "#3a1a55", "#5e2a85", "#8a3fc0", "#b86ef0", "#e0b0ff", "#ffffff"], "seed": 9},
}

static var HUNCH := {"turn": 1, "crouch": 4, "lean": 3, "hy": 1, "fx": -7, "fy": -33, "bx": 8, "by": -33, "ffx": -3, "fbx": 4}
static var act := {
	"onBody": true,
	"poses": [[0, HUNCH], [0.6, Px.merge(HUNCH, {"crouch": 5})], [1.2, Px.merge(HUNCH, {"lean": 2})], [1.8, Px.merge(HUNCH, {"crouch": 5})], [2.4, HUNCH]],
}

static var D: float = meta.duration
static var SKULL := Lib.bitmap([
	"...#####...",
	".#########.",
	"###########",
	"##eee#eee##",
	"##eEe#eEe##",
	"##eee#eee##",
	"#####.#####",
	".####.####.",
	"..#######..",
	"..#.#.#.#..",
	"...#####...",
])
# the skull's life in the loop: hidden, glitching in, hanging there, glitching out
const IN := 0.5
const HOLD := 0.75
const OUT := 1.85
const GONE := 2.1

# how high the stain has crept at column x (0 at the feet, 1 at the head), a slow tide with crawling tendrils
static func tide(t: float) -> float:
	return 0.3 + 0.12 * sin((t / D) * TAU)
static func reach(x: float, t: float, seed: float) -> float:
	return tide(t) + 0.13 * Px.tileFbm(x * 0.35, (t / D) * 4.0, 0.0, 4.0, seed, 2)


# smoke trails: each rises from a spot on the body as a ribbon of soft puffs that wind as they climb, swell, cool
# and thin
static func trails(p: Px.Painter, C: Array, a: Dictionary, S: Dictionary, t: float, _seed: float, front: bool) -> void:
	var spots := [[0.12, -1], [0.1, 1], [0.5, -1], [0.48, 1]]
	for j in spots.size():
		var q: float = spots[j][0]
		var side: int = spots[j][1]
		if (j % 2 == 0) != front:
			continue
		var my := Px.roundi(S.h * q)
		var lr: Array = S.rows[my] if (my >= 0 and my < S.rows.size()) else [0, 0]
		var l: int = lr[0]
		var r: int = lr[1]
		var x0: float = a.x + (l if side < 0 else r + 1)
		var y0: float = a.y + my
		var life := 1.6
		var n := 18
		var i := n - 1
		while i >= 0:
			var age := fmod(fmod(t - (i / float(n)) * D - j * 0.37, D) + D, D)
			var tb := t - age
			var u := age / life
			if u >= 1.0:
				i -= 1
				continue
			var sway := sin((tb / D) * TAU * 2.0 + j * 1.7) * 4.0 * minf(1.0, u * 1.6)
			var x := x0 + side * u * 7.0 + sway + (Px.rand(i, j, 71) - 0.5) * 2.5 * u
			var y := y0 - age * 19.0 - 5.0 * u * u
			var rad := (1.3 + 3.6 * (1.0 - pow(1.0 - u, 3.0))) * (0.7 + 0.6 * Px.rand(i, j, 72))
			var k := Px.smooth(0.0, 0.12, u) * (1.0 - Px.smooth(0.45, 1.0, u)) * (0.5 if front else 0.62)
			var c := Px.mix(C[4] if Px.rand(i, j, 70) < 0.5 else Px.mix(C[4], C[3], 0.4), C[1], u * 0.85)
			p.disc(x, y, rad * 1.08, c, k * 0.4)
			p.disc(x + rad * 0.05, y + rad * 0.08, rad * 0.76, c, k * 0.55)
			p.disc(x - rad * 0.22, y - rad * 0.3, rad * 0.48, Px.mix(c, C[6], 0.25), k * 0.38 * (1.0 - u * 0.6))
			if i % 3 == 0:
				p.glow(x, y, rad * 1.6, C[4], 0.08 * k)
			i -= 1


static func drawBack(p: Px.Painter, t: float, o: Dictionary) -> void:
	var C := Px.fit(o.palette, 8)
	var a: Dictionary = o.actor
	var S := Lib.shape(a)
	# the stain pooling round the feet, its rim glowing
	var flr: Array = S.rows[S.h - 1]
	var fl: int = flr[0]
	var fr: int = flr[1]
	var cx: float = a.x + (fl + fr + 1) / 2.0
	var rx := (fr - fl) / 2.0 + 7.0 + 2.0 * sin((t / D) * TAU)
	for x in range(floori(cx - rx - 1.0), floori(cx + rx + 1.0) + 1):
		var q := absf(x + 0.5 - cx) / rx
		var n := Px.rand(x, 31)
		if q > 1.0 + n * 0.12:
			continue
		p.px(x, 0.0, C[4] if q > 0.8 else (C[3] if n < 0.2 else C[2]))
		if q < 0.85:
			p.px(x, 1.0, C[1])
		if q < 0.55 and n < 0.7:
			p.px(x, 2.0, C[1])
	p.shade(cx - rx - 6.0, -4.0, cx + rx + 6.0, 5.0, func(x, y, out):
		var d := Px.hypot((x - cx) / (rx + 6.0), y / 4.0)
		if d < 1.0:
			out.l = C[4]
			out.k = 0.2 * (1.0 - d) * (1.0 - d))
	trails(p, C, a, S, t, o.seed, false)


static func draw(p: Px.Painter, t: float, o: Dictionary) -> void:
	var C := Px.fit(o.palette, 8)
	var a: Dictionary = o.actor
	var S := Lib.shape(a)
	var H: int = S.h
	# the stain on the body: everything below the creeping line drowned in violet, the line itself burning
	for b: Array in S.body:
		var mx: int = b[0]
		var my: int = b[1]
		var c := Lib.colorAt(a, mx, my)
		var up := 1.0 - (my + 0.5) / H
		var lv := reach(mx, t, o.seed)
		if up > lv + 0.035:
			continue
		var x: int = a.x + mx
		var y: int = a.y + my
		if up > lv - 0.02:
			p.px(x, y, C[6])
		elif up > lv - 0.06:
			p.px(x, y, C[4])
		else:
			p.px(x, y, Px.mix(C[1], C[3], Px.clamp(Px.luma(c) * 1.6)))
	for mx in S.w:
		var lv := reach(mx, t, o.seed)
		var my := floori((1.0 - lv) * H)
		if S.on.call(mx, my):
			p.glow(a.x + mx, a.y + my, 4.0, C[5], 0.14)
	# the eyes burn
	for e: Dictionary in Lib.eyes(a):
		for xy: Array in e.px:
			p.px(a.x + xy[0], a.y + xy[1], C[7] if xy[1] == e.y0 else C[5])
		p.glow(a.x + (e.x0 + e.x1 + 1) / 2.0, a.y + (e.y0 + e.y1 + 1) / 2.0, 5.0, C[5], 0.4)
	trails(p, C, a, S, t, o.seed, true)
	# the skull glitches in, hangs there bobbing, and glitches out
	if t >= IN and t < GONE:
		var glitch := (1.0 - (t - IN) / (HOLD - IN)) if t < HOLD else ((t - OUT) / (GONE - OUT) if t > OUT else 0.0)
		var f := floori(t * 30.0)
		var on := glitch < 0.15 or Px.rand(f, 3) > glitch * 0.6
		var x := 0.0
		var y: float = a.y - 12.0 + sin((t / D) * TAU * 2.0) * 1.2
		if on:
			var tear := func(dx: int, dy: int) -> String:
				var row := dy + 6
				var shift := Px.round((Px.rand(f, row, 9) - 0.5) * 6.0 * glitch) if (glitch > 0.0 and Px.rand(f, row >> 1, 7) < glitch * 0.8) else 0.0
				return SKULL.call(dx - shift, dy)
			if glitch > 0.0:
				Lib.icon(p, x - 2.0, y, 7, tear, [0, C[2], C[2], C[3]], 0.7 * glitch)
				Lib.icon(p, x + 2.0, y, 7, tear, [0, C[6], C[6], C[6]], 0.5 * glitch)
			Lib.icon(p, x, y, 8, tear, [C[0], C[4], C[6], C[7]], 1.0, {"e": C[0], "E": C[7]})
			p.glow(x - 3.0, y - 1.0, 5.0, C[5], 0.6)
			p.glow(x + 3.0, y - 1.0, 5.0, C[5], 0.6)
			p.glow(x, y, 16.0, C[4], 0.24 + 0.3 * glitch)
		# scanlines fizzing as it comes and goes
		if glitch > 0.1:
			for k in 3:
				var ly := y - 5.0 + floorf(Px.rand(f, k, 11) * 11.0)
				var lx := Px.round((Px.rand(f, k, 12) - 0.5) * 10.0)
				var len := 3.0 + floorf(Px.rand(f, k, 13) * 8.0)
				p.line(lx - len / 2.0, ly, lx + len / 2.0, ly, C[6] if k % 2 else C[4], glitch)
	p.glow(0.0, a.y + H * (1.0 - tide(t)), 24.0, C[4], 0.2)
	p.glow(0.0, a.y + H * 0.45, 30.0, C[3], 0.12)
