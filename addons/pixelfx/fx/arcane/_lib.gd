# Shared by the arcane effects: a dithered light ramp, closed-form motes and streaks for loops, crackling
# arcs, floor rings and an original rune alphabet. Files starting with _ are helpers, not effects.
# The dithered ramp (tone) is adapted from Sprite Fusion's open-source black hole
# (https://www.spritefusion.com/pixel-art-vfx/black-hole), and the arc drawing from its energy
# (https://www.spritefusion.com/pixel-art-vfx/energy), MIT License, Copyright (c) 2026 Hugo Duprez.
# port-of: src/fx/arcane/_lib.js@ce40f1a53c5ae66184faf4a38ea3409f8d455541
extends RefCounted

const Px := preload("../../core/px.gd")
const WHITE := Px.WHITE

static var BAYER: Array = [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5].map(func(v): return (v + 0.5) / 16.0)
const CROSS := [[1, 0], [-1, 0], [0, 1], [0, -1]]
## The 4x4 ordered-dither threshold (0..1) of the pixel cell holding (x, y).
static func bayer(x: float, y: float) -> float:
	return BAYER[((floori(y) & 3) << 2) | (floori(x) & 3)]


## Light intensity I (0..1) to a step of ramp R (dark to bright), dithering between neighbouring steps so a
## gradient reads smooth at 1x; below lo it thins out through the dither and returns 0 (draw nothing).
static func tone(R: Array, I: float, x: float, y: float, lo: float = 0.06, sharp: float = 0.0) -> int:
	var b := bayer(x, y)
	if I < lo and b > I / lo:
		return 0
	var n := R.size() - 1
	var f := Px.clamp(I) * n
	var i := floori(f)
	# sharp (0..1) narrows the dithered zone between two steps, so broad areas stay clean and only edges dither
	var q := Px.clamp((f - i - 0.5) / (1.0 - sharp) + 0.5) if sharp > 0.0 else f - i
	if q > b:
		i = mini(n, i + 1)
	return R[i]


## A drifting mote at (x, y) moving (vx, vy) px/s, drawn like the sim's MOTE: bright head, darker tail, light.
static func mote(p: Px.Painter, x: float, y: float, vx: float, vy: float, c: int, size: float = 1.0, k: float = 1.0, glow: float = 0.4) -> void:
	var sp := Px.hypot(vx, vy)
	if not sp:
		sp = 1.0
	var ux := vx / sp
	var uy := vy / sp
	var ln := minf(16.0, 0.5 + sp * 0.026) * size
	var a := k / 0.35 if k < 0.35 else 1.0
	if ln > 1.2:
		p.line(x - ux * ln, y - uy * ln, x - ux * ln * 0.35, y - uy * ln * 0.35, Px.scale(c, 0.55), a)
	p.line(x - ux * ln * 0.4, y - uy * ln * 0.4, x, y, c, a)
	if glow > 0.0:
		p.glow(x, y, 2.5 + size, c, glow * k)


## Energy rushing in, drawn like the sim's STREAK: a white tip, a colored body, a dim dotted tail.
static func streak(p: Px.Painter, x: float, y: float, vx: float, vy: float, c: int, a: float = 1.0, maxLen: float = 7.0, glow: float = 0.4) -> void:
	var sp := Px.hypot(vx, vy)
	if not sp:
		sp = 1.0
	var ux := vx / sp
	var uy := vy / sp
	var L := Px.clamp(sp / 30.0, 1.0, maxLen)
	var d := L
	while d >= 0.0:
		p.dot(x - ux * d, y - uy * d, WHITE if d < 1.0 else (c if d < L * 0.5 else Px.scale(c, 0.6)), (1.0 if d < L * 0.5 else 1.2 - d / L) * a)
		d -= 0.5
	if glow > 0.0:
		p.glow(x, y, 4.0, c, glow * a)


## A crackling arc from (x0, y0) to (x1, y1): a jagged main path plus forks, as [{ pts, w }]. r is an Rng, so
## re-seed it every couple of frames for flicker. opts: { jag = 0.3, forks = 1, forkLen = 0.5 }.
static func arc(r: Px.Rng, x0: float, y0: float, x1: float, y1: float, opts: Dictionary = {}) -> Array:
	var jag: float = opts.get("jag", 0.3)
	var forks: float = opts.get("forks", 1.0)
	var forkLen: float = opts.get("forkLen", 0.5)
	var L := Px.hypot(x1 - x0, y1 - y0)
	var depth := maxf(1.0, minf(5.0, Px.round(log(L / 1.5) / log(2.0))))
	var main := Px.bolt(r, x0, y0, x1, y1, {"jag": jag, "depth": depth})
	var out := [{"pts": main, "w": 1.0}]
	var k := 0
	while k < forks and main.size() > 3:
		if r.next() > 0.7:
			k += 1
			continue
		var i := 1 + floori(r.next() * (main.size() - 2))
		var x: float = main[i][0]
		var y: float = main[i][1]
		var px: float = main[i - 1][0]
		var py: float = main[i - 1][1]
		var a := atan2(y - py, x - px) + (-1.0 if r.next() < 0.5 else 1.0) * (0.4 + r.next() * 0.6)
		var l := L * forkLen * (0.4 + 0.6 * r.next()) * (1.0 - float(i) / main.size())
		if l > 1.5:
			out.append({"pts": Px.bolt(r, x, y, x + cos(a) * l, y + sin(a) * l, {"jag": jag * 1.1, "depth": maxf(1.0, depth - 2.0)}), "w": 0.55})
		k += 1
	return out


## Draw arc paths the way Sprite Fusion draws its bolts: a dithered halo while it's fresh, a body beside the
## core, a white core, light along the path. cols: { core, body, halo, glow }; k: 1 fresh .. 0 gone.
static func drawArc(p: Px.Painter, paths: Array, cols: Dictionary, k: float = 1.0, glowK: float = 0.5) -> void:
	var steps := func(fn: Callable) -> void:
		for path: Dictionary in paths:
			var pts: Array = path.pts
			for i in pts.size() - 1:
				var ax: float = pts[i][0]
				var ay: float = pts[i][1]
				var bx: float = pts[i + 1][0]
				var by: float = pts[i + 1][1]
				var l := maxf(1.0, Px.hypot(bx - ax, by - ay))
				var d := 0.0
				while d <= l:
					fn.call(ax + ((bx - ax) * d) / l, ay + ((by - ay) * d) / l, path, i, d == 0.0)
					d += 0.5
	if k > 0.45:
		steps.call(func(x: float, y: float, path: Dictionary, _i: int, _first: bool) -> void:
			if path.w >= 1.0:
				for o in CROSS:
					p.dot(x + o[0] * 1.5, y + o[1] * 1.5, cols.halo, (k - 0.45) * 1.6))
	if k > 0.25:
		steps.call(func(x: float, y: float, path: Dictionary, _i: int, _first: bool) -> void:
			if path.w > 0.4:
				p.dot(x + 1.0, y, cols.body)
				p.dot(x, y + 1.0, cols.body))
	steps.call(func(x: float, y: float, path: Dictionary, i: int, first: bool) -> void:
		p.px(x, y, cols.core if path.w >= 1.0 and k > 0.3 else cols.body)
		if first and i % 3 == 0:
			p.glow(x, y, (9.0 if path.w >= 1.0 else 5.0) * (0.5 + k * 0.5), cols.glow, glowK * k * path.w))


## A ring lying on the floor (or any tilted plane): centre (cx, cy), radius r, squashed by sy, 1 px thick at
## any size. c and a may be Callables of the angle g around it (sin(g) > 0 is the near side, towards the viewer).
## keep(g) picks which part to draw: func(g): return sin(g) < 0 is the far half, for drawBack.
static func floorRing(p: Px.Painter, cx: float, cy: float, r: float, sy: float, c: Variant, a: Variant = 1.0, keep: Variant = null) -> void:
	if r < 0.5:
		return
	var fc := c is Callable
	var fa := a is Callable
	var ry := r * sy
	p.shade(cx - r - 1.0, cy - ry - 1.0, cx + r + 1.0, cy + ry + 1.0, func(x: float, y: float, o) -> void:
		var nx := (x - cx) / r
		var ny := (y - cy) / maxf(0.3, ry)
		var d := Px.hypot(nx, ny)
		if d < 1e-6:
			return
		var g := Px.hypot(nx / r, ny / maxf(0.3, ry)) / d
		if absf(d - 1.0) / g > 0.5:
			return
		var ang := atan2(ny, nx)
		if keep != null and not keep.call(ang):
			return
		o.c = c.call(ang) if fc else c
		o.a = a.call(ang) if fa else a)


# An original rune alphabet: angular 3 x 5 glyphs that stay readable standing upright at 1x.
const GLYPHS := [
	[".#.", "#.#", ".#.", ".#.", "#.#"],
	["#.#", "#.#", ".#.", "#.#", "#.#"],
	["##.", "#.#", "##.", "#..", "#.."],
	["#..", "#.#", "###", "#.#", "..#"],
	[".##", "#..", ".#.", "..#", "##."],
	["###", ".#.", "###", ".#.", ".#."],
	["#.#", "###", "#.#", "..#", "..#"],
	[".#.", ".##", ".#.", "##.", ".#."],
]

## Rune i standing on (x, y): its bottom row sits on y, centred on x. c body color, a alpha (dithered), under an
## optional darker color drawn a pixel lower so the glyph has a little thickness.
static func glyph(p: Px.Painter, i: int, x: float, y: float, c: int, a: float = 1.0, under: int = 0) -> void:
	var g: Array = GLYPHS[((i % GLYPHS.size()) + GLYPHS.size()) % GLYPHS.size()]
	var X := Px.round(x) - 1.0
	var Y := Px.round(y) - g.size() + 1.0
	if under:
		p.sprite(g, {}, X, Y + 1.0, {"tint": under, "a": a})
	p.sprite(g, {}, X, Y, {"tint": c, "a": a})


# Larger original sigils, 5 x 7, for runes that fly or hover on their own.
const SIGILS := [
	["..#..", ".#.#.", "#.#.#", "..#..", ".###.", "..#..", ".#.#."],
	["#...#", ".#.#.", "..#..", ".###.", "..#..", ".#.#.", "#...#"],
	["#....", "##...", "#.#..", "#..#.", "#.#..", "##...", "#...."],
	["..#..", "#.#.#", ".###.", "..#..", "..#..", ".#.#.", "#...#"],
	["#.#.#", "#.#.#", "#####", "..#..", "..#..", "..#..", ".###."],
	["#...#", "##.##", "#.#.#", "#...#", "#.#.#", "##.##", "#...#"],
	["..#..", ".#.#.", "#...#", ".#.#.", "..#..", "..#..", "..#.."],
	["#..#.", "#.#..", "##...", "#....", "##...", "#.#..", "#..#."],
]

## Sigil i centred on (x, y) in color c, ringed by a 1 px edge in a darker color so it reads against anything.
static func sigil(p: Px.Painter, i: int, x: float, y: float, c: int, a: float = 1.0, edge: int = 0) -> void:
	var g: Array = SIGILS[((i % SIGILS.size()) + SIGILS.size()) % SIGILS.size()]
	var X := Px.round(x) - 2.0
	var Y := Px.round(y) - 3.0
	if edge:
		for o in CROSS:
			p.sprite(g, {}, X + o[0], Y + o[1], {"tint": edge, "a": a})
	p.sprite(g, {}, X, Y, {"tint": c, "a": a})


## A character's silhouette shaded by how light each pixel is: 1 its dark outline, 2 mid, 3 light (0 empty).
static func shades(A: Dictionary) -> PackedByteArray:
	var s := PackedByteArray()
	var Aw: int = A.w
	var Ah: int = A.h
	s.resize(Aw * Ah)
	var data: PackedByteArray = A.mask.data
	var has_px: bool = A.get("pixels") != null
	for i in s.size():
		if data[i]:
			s[i] = (1 if Px.luma(A.pixels[i]) < 0.24 else (2 if Px.luma(A.pixels[i]) < 0.62 else 3)) if has_px else 2
	return s


## Silhouette A (an actor) squeezed to sx of its width about its middle and shifted by dx: body color on its
## pixels, edge color on its dark outline pixels. sh is shades(A). The blink's squeeze, adapted from Sprite Fusion.
static func squeezed(p: Px.Painter, A: Dictionary, sh: PackedByteArray, sx: float, body: int, edge: int, a: float = 1.0, dx: float = 0.0) -> void:
	if sx <= 0.02:
		return
	var Ax: int = A.x
	var Ay: int = A.y
	var Aw: int = A.w
	var Ah: int = A.h
	var cx := Ax + Aw / 2.0
	var half := Aw / 2.0 + 1.0
	for y in Ah:
		for x in range(floori(cx - half * sx), ceili(cx + half * sx) + 1):
			var i := Px.roundi(cx + (x + 0.5 - cx) / sx - 0.5) - Ax
			var v := 0 if (i < 0 or i >= Aw) else sh[y * Aw + i]
			if v:
				p.dot(x + dx, Ay + y, edge if v == 1 else body, a)
