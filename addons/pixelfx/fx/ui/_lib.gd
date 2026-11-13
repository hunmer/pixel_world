# Helpers for the ui effects (not an effect: the file name starts with _). Big pixel words with a hand-made
# finish, a character lit or flashed by the effect, HUD plates and a whole-pixel shake.
# tintActor adapts the body flash of Sprite Fusion's open-source power-up
# (https://www.spritefusion.com/pixel-art-vfx/power-up), MIT License, Copyright (c) 2026 Hugo Duprez.
# port-of: src/fx/ui/_lib.js@86cbc0d222a52738e693aa14d750eb34182403f2
extends RefCounted

const Px := preload("../../core/px.gd")
const WHITE := Px.WHITE


## The letters of str in a pixel font, laid out left to right in font pixels:
## { letters: [{ ch, g (glyph, null for a space), x (left edge), w, h }], w (total width), h }.
## (x, w and the total width are floats here, so effects can divide them freely.)
static func spell(s: Variant, font: String = "big") -> Dictionary:
	var F: Dictionary = Px.fonts()[font]
	var letters := []
	var x := 0.0
	for ch in str(s):
		var g: Variant = F.glyphs.get(ch)
		if g == null:
			g = F.glyphs.get(ch.to_upper())
		var w: float = g.w if g != null else F.space
		letters.append({"ch": ch, "g": g, "x": x, "w": w, "h": F.h})
		x += w + F.gap
	return {"letters": letters, "w": maxf(0.0, x - F.gap), "h": F.h}


static func _buf32(n: int) -> PackedInt32Array:
	var b := PackedInt32Array()
	b.resize(n)
	return b


static func _buf8(n: int) -> PackedByteArray:
	var b := PackedByteArray()
	b.resize(n)
	return b


# scratch maps of which letter covers each pixel and where it sits in its font pixel, reused between frames
static var ids := _buf32(4096)
static var edges := _buf8(4096)


# a row of a glyph is open over gx when nothing in it touches that font pixel (JS: out of range reads undefined)
static func _open(r: Variant, gx: int) -> bool:
	if r == null:
		return true
	var a: Array = r
	return not a[gx] and not (gx > 0 and a[gx - 1]) and not (gx + 1 < a.size() and a[gx + 1])


## Draw letters as one word with a crafted finish at the 1 px level: a gradient down each letter, a lit top
## edge, a shaded underside, a 1 px dark outline and a drop shadow, an optional diagonal shine and a white flash.
## items: [{ g (glyph), x, y (top-left, local px), sx, sy (px per font pixel), a (alpha), flash (0..1 white),
## slant (italics: px of lean per font row, stepped in whole pixels) }]. st: { fill: [bottom..top colors], edge (lit top edge), under (underside),
## outline, ow (outline width, 1 or 2), shadow, shine (diagonal position, local x at the word's top row), shineY,
## glint: color beside the shine's white core }.
static func drawWord(p: Px.Painter, items: Array, st: Dictionary) -> void:
	if not items.size():
		return
	var x0f := INF
	var y0f := INF
	var x1f := -INF
	var y1f := -INF
	for it: Dictionary in items:
		var gn: int = it.g.rows.size()
		var h: float = gn * it.sy
		var w: float = it.g.w * it.sx
		var sl: float = absf(it.get("slant", 0.0)) * gn
		x0f = minf(x0f, it.x - sl)
		x1f = maxf(x1f, it.x + w + sl)
		y0f = minf(y0f, it.y)
		y1f = maxf(y1f, it.y + h)
	var ow: int = int(st.get("ow", 1))
	var x0 := floori(x0f) - 1 - ow
	var y0 := floori(y0f) - 1 - ow
	var x1 := ceili(x1f) + 2 + ow
	var y1 := ceili(y1f) + 3 + ow
	var W := x1 - x0
	var H := y1 - y0
	# (here the maps carry a border of pad empty pixels round the box, so the reads round a pixel need no bounds
	# checks: the border reads 0, as the JS `at` does outside the box)
	var pad := ow + 1
	var PW := W + 2 * pad
	var NP := PW * (H + 2 * pad)
	if NP > ids.size():
		ids = _buf32(NP * 2)
		edges = _buf8(NP * 2)
	ids.fill(0)
	var WH := W * H
	for k in items.size():
		var it: Dictionary = items[k]
		var g: Dictionary = it.g
		var rows: Array = g.rows
		var gh := rows.size()
		var gw: int = g.w
		var ix: float = it.x
		var iy: float = it.y
		var isx: float = it.sx
		var isy: float = it.sy
		var h := gh * isy
		var bot := iy + h
		var sl: float = it.get("slant", 0.0)
		for py in range(floori(iy), ceili(bot)):
			var gy := floori((py + 0.5 - iy) / isy)
			if gy < 0 or gy >= gh:
				continue
			var shift := Px.round(((bot - py - 0.5) / isy) * sl)
			var ry := py + 0.5 - iy - gy * isy
			var row: Array = rows[gy]
			var up: Variant = rows[gy - 1] if gy > 0 else null
			var dn: Variant = rows[gy + 1] if gy < gh - 1 else null
			for px in range(floori(ix + shift) - 1, ceili(ix + shift + gw * isx) + 1):
				var fx := px + 0.5 - ix - shift
				var gx := floori(fx / isx)
				if gx < 0 or gx >= gw or not row[gx]:
					continue
				var i := (py - y0) * W + (px - x0)
				if i < 0 or i >= WH:
					continue
				# the same pixel in the bordered map (the row and column of i, as the JS reads it back)
				var iyy := floori(float(i) / W)
				var q := (iyy + pad) * PW + (i - iyy * W) + pad
				ids[q] = k + 1
				# the bevel follows the font pixels, so italic steps don't break it: lit top, shaded underside, lit left.
				# Only flat edges get it: a diagonal stroke (a font pixel touching one corner to corner) stays whole.
				var rx := fx - gx * isx
				edges[q] = (1 if (ry < 1.0 and _open(up, gx)) else 0) | (2 if (ry >= isy - 1.0 and _open(dn, gx)) else 0) | (4 if (rx < 1.0 and not (gx > 0 and row[gx - 1])) else 0)
	var I := ids
	var E := edges
	var F: Array = st.fill
	var nF := F.size()
	var shine: Variant = st.get("shine")
	var hasShine := shine != null
	var shn: float = shine if hasShine else 0.0
	var glint: int = st.glint if st.get("glint") != null else WHITE
	var sy0: float = st.shineY if st.get("shineY") != null else float(y0)
	var cEdge: int = st.edge if st.get("edge") != null else F[nF - 1]
	var cUnder: int = st.under if st.get("under") != null else F[0]
	var outline: int = st.get("outline", 0)
	var shadow: int = st.get("shadow", 0)
	# each item's numbers, read once: top, height, flash, alpha
	var nI := items.size()
	var iY := PackedFloat64Array()
	var iH := PackedFloat64Array()
	var iF := PackedFloat64Array()
	var iA := PackedFloat64Array()
	iY.resize(nI)
	iH.resize(nI)
	iF.resize(nI)
	iA.resize(nI)
	for k in nI:
		var it: Dictionary = items[k]
		iY[k] = it.y
		iH[k] = it.g.rows.size() * it.sy
		iF[k] = it.get("flash", 0.0)
		iA[k] = it.get("a", 1.0)
	# the outline's neighbours, in the order the JS visits them, and the three shadow reads
	var OFF := PackedInt32Array()
	for dy in range(-ow, ow + 1):
		for dx in range(-ow, ow + 1):
			if ow < 2 or absi(dx) + absi(dy) < 4:
				OFF.append(dy * PW + dx)
	var S1 := (-1 - ow) * PW - ow
	var S2 := (-1 - ow) * PW + 1 - ow
	var S3 := -ow * PW - ow
	for y in range(y0, y1):
		var rowq := (y - y0 + pad) * PW + pad - x0
		var yc := y + 0.5
		for x in range(x0, x1):
			var q := rowq + x
			var id: int = I[q]
			if id:
				var v: float = (yc - iY[id - 1]) / iH[id - 1]
				var i := mini(nF - 1, maxi(0, floori((1.0 - v) * nF)))
				var c: int = F[i]
				var e := E[q]
				if e & 1:
					c = cEdge
				elif e & 2:
					c = cUnder
				elif e & 4 and i < nF - 1:
					c = F[i + 1]
				if hasShine:
					var d := absf(x + 0.5 - (yc - sy0) * 0.6 - shn)
					if d < 1.1:
						c = WHITE
					elif d < 2.4:
						c = glint
				# a flash is white all over, then wipes up off the letter (no dither)
				var fl := iF[id - 1]
				if fl > 0.6 or (fl > 0.25 and v < 0.5):
					c = WHITE
				p.dot(x, y, c, iA[id - 1])
				continue
			# the outline hugs every letter; the shadow drops below and right of it
			var n := 0
			for off in OFF:
				n = I[q + off]
				if n:
					break
			if n:
				p.dot(x, y, outline, iA[n - 1])
				continue
			var s := I[q + S1]
			if not s:
				s = I[q + S2]
			if not s:
				s = I[q + S3]
			if s and shadow:
				p.dot(x, y, shadow, iA[s - 1] * 0.9)


## Flash a character in light: its own pixels recolored by brightness into a bright ramp ([shadow, middle,
## light] colors). k (0..1) steps down without dither: all of it, then its lighter parts, then only highlights;
## above 0.8 the lightest go white.
static func tintActor(p: Px.Painter, A: Variant, k: float, ramp: Array) -> void:
	if A == null or k <= 0.12:
		return
	var m: Dictionary = A.mask
	var pix: Variant = A.get("pixels")
	var cut := 0.0 if k > 0.6 else (0.22 if k > 0.3 else 0.5)
	var mw: int = m.w
	var mh: int = m.h
	var data: PackedByteArray = m.data
	var ax: float = A.x
	var ay: float = A.y
	for j in mh:
		for i in mw:
			var q := j * mw + i
			if not data[q]:
				continue
			var l: float = Px.luma(pix[q]) if pix != null else 0.6
			if l < cut:
				continue
			p.px(ax + i, ay + j, ((WHITE if k > 0.8 else ramp[2]) if l > 0.5 else (ramp[1] if l > 0.22 else ramp[0])))


static func _has(m: Dictionary, i: int, j: int) -> bool:
	return i >= 0 and j >= 0 and i < m.w and j < m.h and m.data[j * m.w + i]


## Light a character: warm additive light over its body (k), stronger towards the top, and light catching the
## edge just inside its dark outline (rim 0..1), mixed into its own colors so it stays solid and readable.
static func lightActor(p: Px.Painter, A: Variant, c: int, k: float, rim: float = 0.0, t: float = 0.0) -> void:
	if A == null or (k <= 0.01 and rim <= 0.01):
		return
	var m: Dictionary = A.mask
	var pix: Variant = A.get("pixels")
	var mw: int = m.w
	var mh: int = m.h
	var data: PackedByteArray = m.data
	var ax: float = A.x
	var ay: float = A.y
	for j in mh:
		for i in mw:
			if not data[j * mw + i]:
				continue
			if k > 0.01:
				p.light(ax + i, ay + j, c, k * (1.1 - (0.5 * j) / mh))
			if rim <= 0.01 or not _has(m, i - 1, j) or not _has(m, i + 1, j) or not _has(m, i, j - 1):
				continue
			if _has(m, i - 2, j) and _has(m, i + 2, j) and _has(m, i, j - 2):
				continue
			var f := rim * (0.75 + 0.35 * Px.noise(j * 0.6 - t * 8.0, i * 3))
			if f > 0.25:
				var own: int = c
				if pix != null:
					own = pix[j * mw + i] if pix[j * mw + i] else c
				p.px(ax + i, ay + j, Px.mix(own, c, minf(0.85, f)))


## A glowing 1 px line just outside a character, flickering: an aura's edge.
static func haloActor(p: Px.Painter, A: Variant, c: int, k: float, t: float = 0.0) -> void:
	if A == null or k <= 0.02:
		return
	p.outline(A.mask, A.x, A.y, c, func(mx, my): return k * (0.75 + 0.45 * Px.noise(my * 0.45 - t * 7.0, mx * 3)))


## A UI plate: a rounded rectangle with a dark outline, a lit top rim, a body that darkens towards the bottom
## and a shaded bottom edge. col: { outline, rim, top, body, low }. opts: { r (corner), a, shine (diagonal x) }.
static func panel(p: Px.Painter, x: float, y: float, w: float, h: float, col: Dictionary, opts: Dictionary = {}) -> void:
	var r: float = opts.get("r", 3.0)
	var a: float = opts.get("a", 1.0)
	var shine: Variant = opts.get("shine")
	if w < 2.0 or h < 2.0:
		return
	var X1 := x + w
	var Y1 := y + h
	p.shade(x, y, X1, Y1, func(px: float, py: float, o):
		var cx := maxf(maxf(x + r - px, 0.0), px - (X1 - r))
		var cy := maxf(maxf(y + r - py, 0.0), py - (Y1 - r))
		var e := (r - Px.hypot(cx, cy)) if (cx > 0.0 and cy > 0.0) else minf(minf(minf(px - x, X1 - px), py - y), Y1 - py)
		if e < 0.0:
			return null
		o.a = a
		if e < 1.0:
			return col.outline
		if py - y < 2.0:
			return col.rim
		if Y1 - py < 2.0:
			return col.low
		if shine != null:
			var d: float = absf(px - (py - y) * 0.6 - shine)
			if d < 1.3:
				return WHITE
			if d < 3.0:
				return col.rim
		return col.top if py - y < h * 0.45 else col.body)


## A HUD heart, 13 x 12: k outline, w highlight, h light, o body, m shade, d deep shade. heartPal(C) maps a
## ramp onto it (C[0] outline .. C[4] body, white highlight); drawn with p.sprite.
const HEART := [
	"..kkk...kkk..",
	".khhok.khook.",
	"khwhookoooomk",
	"khwoooooooomk",
	"khoooooooommk",
	"kooooooooomdk",
	".kooooooomdk.",
	"..kooooomdk..",
	"...kooomdk...",
	"....komdk....",
	".....kdk.....",
	"......k......",
]


static func heartPal(C: Array) -> Dictionary:
	return {"k": C[0], "w": WHITE, "h": C[5], "o": C[4], "m": C[3], "d": C[2]}


## A whole-pixel shake that dies away: [dx, dy] at time t, amp px, from t0 over len seconds.
static func shake(t: float, amp: float, t0: float = 0.0, len_: float = 0.3, seed: float = 1.0, hz: float = 32.0) -> Array:
	if t < t0 or t > t0 + len_:
		return [0.0, 0.0]
	var k := 1.0 - (t - t0) / len_
	return [Px.round(Px.noise(t * hz, seed) * amp * k * 1.7), Px.round(Px.noise(t * hz, seed + 7.0) * amp * k * 1.3)]
