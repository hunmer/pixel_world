# port-of: src/fx/ui/quest-complete.js@7d83738756ff4ee17a7d4e80e9fd28fff9246e41
extends "../../core/effect.gd"

const Px := preload("../../core/px.gd")
const Lib := preload("_lib.gd")
const P := Px.P
const WHITE := Px.WHITE

static var meta := {
	"name": "Quest complete",
	"desc": "A stitched ribbon unrolls from the middle, QUEST COMPLETE types on letter by letter, a gold seal stamps down and ticks, stars pop; then it all rolls away.",
	"tags": ["ui", "quest", "banner", "reward", "text", "one-shot"],
	"size": [204, 92],
	"origin": [102, 46],
	"duration": 2.6,
	"loop": false,
	"fps": 30,
	"bg": "dark",
	"options": {
		"palette": ["#2a1405", "#5c3008", "#9a5a0e", "#d48e18", "#f5b92c", "#ffde5e", "#fff4bc", "#ffffff"],
		"ribbon": ["#1e0608", "#45101a", "#7a1a26", "#ad2632", "#d8433f", "#f27a5e", "#ffb79a"],
		"text": "QUEST COMPLETE",
		"seed": 8,
	},
}

const L := 66.0
const BH := 8.0
const OPEN := 0.32
const TYPE := 0.2
const STEP := 0.036
const STAMP := 0.95
const SX := 64.0
const SY := 4.0
const POPSEAL := 2.0
const ROLL := 2.08


# the ribbon: two notched tails behind, dark folds, then the band with a lit top, stitching and rolled ends
static func ribbon(p: Px.Painter, Rb: Array, G: Array, l: float, tails: float, t: float) -> void:
	if l < 1.0:
		return
	if tails > 0.02:
		for s in [-1.0, 1.0]:
			var drop := 6.0 * tails
			var x0: float = s * (l - 8.0)
			var x1: float = s * (l + 16.0 * tails)
			p.shade(minf(x0, x1) - 1.0, -BH + drop - 1.0, maxf(x0, x1) + 1.0, BH + drop + 1.0, func(x: float, y: float):
				var u := (x - x0) / (x1 - x0)
				var v := y - drop
				if u < 0.0 or u > 1.0 or absf(v) > BH:
					return null
				# a V notch cut into the far end
				if u > 1.0 - (0.3 * (BH - absf(v))) / BH:
					return null
				var e: float = minf(BH - absf(v), (1.0 - u) * (x1 - x0) * s)
				if e < 1.0 or u < 0.02:
					return Rb[0]
				return Rb[3] if v < -BH + 2.0 else (Rb[2] if v < 0.0 else Rb[1]))
			# the fold where the tail tucks under the band
			p.tri(s * (l - 8.0), BH, s * (l - 1.0), BH, s * (l - 8.0), BH + drop, Rb[0])
	p.shade(-l - 1.0, -BH - 1.0, l + 1.0, BH + 1.0, func(x: float, y: float):
		var ax := absf(x)
		var v := y
		if ax > l or absf(v) > BH:
			return null
		var e := minf(l - ax, BH - absf(v))
		if e < 1.0:
			return Rb[0]
		if v < -BH + 2.0:
			return Rb[5]
		if v > BH - 2.0:
			return Rb[1]
		# gold stitching just inside the top and bottom edges
		if (absf(v + BH - 2.5) < 0.5 or absf(v - BH + 3.5) < 0.5) and floori(x + 0.5) % 3 != 0 and ax < l - 3.0:
			return G[3]
		return Rb[4] if v < -1.0 else Rb[3])
	# while it unrolls, the rolled-up ends ride its edges
	if tails < 0.02:
		for s in [-1.0, 1.0]:
			var x: float = s * l
			p.rect(Px.round(x) - 2.0, -BH - 2.0, 4.0, BH * 2.0 + 4.0, Rb[0])
			p.rect(Px.round(x) - 1.0, -BH - 1.0, 1.0, BH * 2.0 + 2.0, Rb[4])
			p.rect(Px.round(x), -BH - 1.0, 1.0, BH * 2.0 + 2.0, Rb[2])
			p.px(Px.round(x) - 1.0, -BH - 1.0, Rb[6])


# a gold seal: a scalloped rim, a lit face with an inner ring, and a check mark drawn on in progress k
static func seal(p: Px.Painter, G: Array, x: float, y: float, r: float, sx: float, sy: float, white: bool, k: float) -> void:
	var M := r * 1.25 + 2.0
	p.shade(x - M * sx, y - M * sy, x + M * sx, y + M * sy, func(px: float, py: float):
		var dx := (px - x) / sx
		var dy := (py - y) / sy
		var d := Px.hypot(dx, dy)
		var an := atan2(dy, dx)
		var edge := r * (1.0 + 0.09 * cos(an * 14.0))
		if d > edge:
			return null
		if white:
			return G[5] if edge - d < 1.0 else WHITE
		if edge - d < 1.0:
			return G[0]
		var l := -(dx * 0.6 + dy * 0.8) / r
		if edge - d < 3.0:
			return G[6] if l > 0.3 else (G[5] if l > -0.3 else G[3])
		if absf(d - r * 0.66) < 0.5:
			return G[3] if l > 0.0 else G[2]
		return G[7] if l > 0.45 else (G[6] if l > 0.1 else (G[5] if l > -0.35 else G[4])))
	if white or k <= 0.0:
		return
	# the check: a short stroke down, a long one up, white with a dark edge
	var pts := []
	for ab in [[-5.0, 0.0], [-1.5, 3.5], [5.5, -4.5]]:
		pts.append([x + ab[0] * sx, y + ab[1] * sy])
	var len1 := Px.hypot(pts[1][0] - pts[0][0], pts[1][1] - pts[0][1])
	var len2 := Px.hypot(pts[2][0] - pts[1][0], pts[2][1] - pts[1][1])
	var done := k * (len1 + len2)
	var segs := [[pts[0], pts[1], minf(1.0, done / len1)], [pts[1], pts[2], Px.clamp((done - len1) / len2)]]
	for wc in [[4.2, G[0]], [2.4, WHITE]]:
		for sg in segs:
			var a: Array = sg[0]
			var b: Array = sg[1]
			var u: float = sg[2]
			if u > 0.0:
				p.beam(a[0], a[1], a[0] + (b[0] - a[0]) * u, a[1] + (b[1] - a[1]) * u, wc[0], wc[1])


var o: Dictionary
var G: Array
var Rb: Array
var R: Px.Rng
var ps: Px.Particles
var lights: Px.Lights
var word: Dictionary
var TS := 2.0
var TW: float
var TX: float
var TY := -5.0
var glyphs: Array
var sats: Array
var t := 0.0
var stamped := false
var popped := false
var end: float


func create(o_: Dictionary) -> void:
	o = o_
	G = Px.fit(o.palette, 8)
	Rb = Px.fit(o.ribbon, 7)
	R = Px.Rng.new(o.seed)
	ps = Px.Particles.new({"rng": R, "sparks": [G[7], G[6], G[5], G[3]]})
	lights = Px.Lights.new()
	word = Lib.spell(o.text, "mini")
	TW = word.w * TS
	TX = -TW / 2.0 - 4.0
	glyphs = word.letters.filter(func(Lt): return Lt.g != null)
	sats = Px.arr(7, func(i: int): return {"x": (i / 6.0 - 0.5) * 140.0 + R.range(-6.0, 6.0), "y": (1.0 if i % 2 else -1.0) * R.range(15.0, 22.0), "t0": STAMP + 0.12 + i * 0.12 + R.range(0.0, 0.04), "dur": R.range(0.3, 0.45), "L": R.range(3.0, 6.0)})
	end = meta.duration - 0.05


func update(dt: float) -> void:
	t += dt
	if not stamped and t >= STAMP:
		stamped = true
		lights.add(SX, SY, 40.0, G[5], 0.7, 0.35)
		lights.add(SX, SY, 18.0, WHITE, 0.7, 0.1)
		for i in 12:
			var an := (i / 12.0) * TAU + R.range(-0.2, 0.2)
			var sp := R.range(40.0, 80.0) * (0.6 if cos(an) > 0.0 else 1.0)
			ps.spawn(P.STAR, SX + cos(an) * 11.0, SY + sin(an) * 11.0, cos(an) * sp, sin(an) * sp * 0.7, R.range(0.25, 0.45), R.pick([G[7], G[6], G[5]]), 0.6 if i % 3 else R.range(1.2, 1.8))
	# gold motes drift up off the banner while it holds
	if t > STAMP and t < POPSEAL and R.chance(0.08):
		ps.spawn(P.STAR, R.range(-L, L), R.range(-BH, BH), R.range(-5.0, 5.0), -R.range(8.0, 20.0), minf(R.range(0.4, 0.8), end - t), R.pick([G[6], G[5]]), 0.6)
	if not popped and t >= POPSEAL + 0.05:
		popped = true
		lights.add(SX, SY, 30.0, G[6], 0.6, 0.2)
		for i in 8:
			var an := R.range(0.0, TAU)
			var sp := R.range(40.0, 90.0)
			ps.spawn(P.STAR, SX + cos(an) * 6.0, SY + sin(an) * 6.0, cos(an) * sp, sin(an) * sp, minf(R.range(0.25, 0.4), end - t), R.pick([G[7], G[6]]), 0.6 if i % 2 else 1.5)
	ps.update(dt)
	lights.update(dt)


func draw(p: Px.Painter) -> void:
	var jxy := Lib.shake(t, 2.0, STAMP, 0.18, o.seed)
	var jx: float = jxy[0]
	var jy: float = jxy[1]
	# the ribbon unrolls from the middle, and rolls back up at the end
	var l := L * (Px.Ease.outCubic(Px.seg(t, 0.0, OPEN)) if t < ROLL else 1.0 - Px.Ease.inCubic(Px.seg(t, ROLL, ROLL + 0.26)))
	var tails := Px.seg(t, OPEN - 0.02, OPEN + 0.12) * (1.0 if t < ROLL else 0.0)
	var sh := Px.seg(t, 1.2, 1.5)
	var shine: Variant = -L - 10.0 + (2.0 * L + 20.0) * sh if (sh > 0.0 and sh < 1.0) else null
	ribbon(p, Rb, G, l, Px.Ease.outBack(tails, 2.0), t)
	if shine != null:
		var y := -BH + 1.0
		while y < BH:
			var x: float = shine + (y + BH) * 0.6
			if absf(x) < l - 2.0:
				p.px(x, y, Rb[6])
				p.px(x + 1.0, y, Rb[5])
			y += 1.0
	# the words type on, each letter popping in white, clipped by the ribbon as it rolls away
	var items := []
	for i in glyphs.size():
		var Lt: Dictionary = glyphs[i]
		var u := t - (TYPE + i * STEP)
		var x: float = TX + Lt.x * TS + jx
		if u < 0.0 or absf(x + Lt.w) > l - 3.0:
			continue
		var s := 2.6 if u < 0.035 else TS
		items.append({"g": Lt.g, "x": x - ((s - TS) * Lt.w) / 2.0, "y": TY + jy - ((s - TS) * 5.0) / 2.0, "sx": s, "sy": s, "flash": 1.0 if u < 0.07 else 0.0})
	Lib.drawWord(p, items, {"fill": [G[4], G[5], G[6], G[7]], "edge": WHITE, "under": G[3], "outline": Rb[0], "shadow": Rb[1]})
	# the seal: drops in big and faint, stamps with a squash and a flash, ticks, pops at the end
	var dk := Px.seg(t, STAMP - 0.12, STAMP)
	var pk := t - POPSEAL
	if dk > 0.0 and pk < 0.08:
		var fall := 1.0 - Px.Ease.inQuad(dk)
		var sq := exp(-(t - STAMP) * 30.0) * (1.0 if t >= STAMP else 0.0)
		var s := 1.0 + 0.8 * fall
		var sx := s * (1.0 + 0.2 * sq)
		var sy := s * (1.0 - 0.2 * sq)
		if pk > 0.0:
			sx = 1.0 + 0.3 * (pk / 0.08)
			sy = sx
		var white := (t >= STAMP and t < STAMP + 0.05) or pk > 0.0
		if dk < 1.0:
			p.ellipse(SX, SY + 12.0, 10.0 * (1.0 - 0.3 * fall), 2.0, Rb[0], 0.5 * dk)
		seal(p, G, SX + jx, SY - 14.0 * fall + jy, 11.0, sx, sy, white, Px.seg(t, STAMP + 0.08, STAMP + 0.24))
		p.glow(SX, SY, 22.0, G[5], 0.3 + (0.4 if white else 0.0))
	var rk := (t - STAMP) / 0.3
	var rr := 12.0 + 13.0 * Px.Ease.outCubic(rk)
	if rk > 0.0 and rk < 1.0:
		p.ellipse(SX, SY, rr * 1.15, rr, WHITE if rk < 0.3 else G[5], func(d: float): return 1.2 - rk if d > 1.0 - 1.4 / rr else 0.0)
	# stars pop round the banner one after another
	for s: Dictionary in sats:
		var u: float = (t - s.t0) / s.dur
		if u > 0.0 and u < 1.0:
			Px.sparkle(p, s.x, s.y, s.L * pow(sin(u * PI), 0.7), G[6], G[5], 0.5)
	ps.draw(p)
	p.glow(0.0, 0.0, 76.0, G[4], 0.2 * Px.seg(t, 0.2, 0.5) * (1.0 - Px.seg(t, ROLL, ROLL + 0.2)))
	lights.draw(p)
