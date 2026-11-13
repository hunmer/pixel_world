# port-of: src/fx/critters/eyeball.js@54f541c6bb691e9e18e6adf435ca3b97a68d17d0
extends RefCounted

const Px := preload("../../core/px.gd")
const Lib := preload("_lib.gd")

static var meta := {
	"name": "Eyeball",
	"desc": "A bloodshot eyeball floats in its fleshy lids: its glowing iris snaps from one look to the next, it blinks, and its nerve sways behind it as it bobs.",
	"tags": ["critter", "eyeball", "eye", "monster", "spooky", "float", "loop"],
	"size": [96, 108],
	"origin": [48, 100],
	"duration": 3.2,
	"loop": true,
	"fps": 30,
	"bg": "ground",
	"options": {
		"palette": ["#2a1420", "#6a3040", "#b07078", "#dcbcb4", "#f4e9de", "#ffffff"],
		"flesh": ["#1e0c16", "#4a1a2c", "#7c2c40", "#b04a58", "#e07a80"],
		"iris": ["#0c2a14", "#1f6a2a", "#3fae3a", "#9be05a", "#e8ffb0"],
		"hover": 48,
		"seed": 1,
	},
}

static var D: float = meta.duration
static var GRID := Lib.Grid.new(-18, -18, 36, 38)
static var NERVE := Lib.Grid.new(-20, -70, 40, 64)
const R := 13.0
static var VEIN := Px.hex("#c42a3a")
# where it looks: snaps between targets with a little overshoot, holds, snaps on
const LOOKS := [[0.0, 0.0, 0.0], [0.55, 4.2, -1.2], [1.15, -4.4, 0.8], [1.95, 1.2, 3.4], [2.5, -2.0, -3.4], [3.0, 0.0, 0.0]]


static func look(t: float) -> Array:
	var i := LOOKS.size() - 1
	while i > 0 and t < LOOKS[i][0]:
		i -= 1
	var t0: float = LOOKS[i][0]
	var x1: float = LOOKS[i][1]
	var y1: float = LOOKS[i][2]
	var prev: Array = LOOKS[(i + LOOKS.size() - 1) % LOOKS.size()]
	var x0: float = prev[1]
	var y0: float = prev[2]
	var u := Px.Ease.outBack(Px.clamp((t - t0) / 0.08), 2.2)
	return [Px.lerp(x0, x1, u), Px.lerp(y0, y1, u)]


# the lids: open at rest, a quick blink before it looks down
static func lid(t: float) -> float:
	return sin(PI * ((t - 1.74) / 0.18)) if (t > 1.74 and t < 1.92) else 0.0


static func at(t: float, hover: float) -> Dictionary:
	var a := (t / D) * TAU
	return {"x": 1.5 * sin(a), "y": -hover - 3.0 * sin(2.0 * a + 0.4)}


# veins: branching red threads creeping in from the rim, fixed to the eyeball's surface
static func veins(seed: float) -> Array:
	var out := []
	var r := Px.rng(seed, 77)
	for i in 7:
		var a := (i / 7.0) * TAU + r.range(-0.3, 0.3)
		var d := R - 0.5
		var pts := [[cos(a) * d, sin(a) * d]]
		for k in 4:
			a += r.range(-0.35, 0.35)
			d -= r.range(1.2, 2.1)
			pts.append([cos(a) * d, sin(a) * d])
		out.append(pts)
	return out


static func eye(g: Lib.Grid, C: Array, Fl: Array, I: Array, t: float, seed: float) -> void:
	g.clear()
	var lxy := look(t)
	var lx: float = lxy[0]
	var ly: float = lxy[1]
	var L := lid(t)
	var V := veins(seed)
	var lit := func(x: float, y: float, k: float) -> bool:
		return Px.hypot(-4.0 + (x + 4.0) / k, -4.5 + (y + 4.5) / k) <= R
	# the sclera: a wet sphere lit from the top-left, pinker in its shadow
	g.shade(-R, -R, R, R, func(x, y):
		var d := Px.hypot(x, y)
		if d > R:
			return 0
		if not (Px.hypot(x + 2.0, y + 2.2) <= R):
			return C[2]
		return C[5] if lit.call(x, y, 0.5) else (C[4] if lit.call(x, y, 0.8) else C[3]))
	# veins ride the eyeball as it turns
	for pts in V:
		var sh := []
		for q in pts:
			var x: float = q[0]
			var y: float = q[1]
			sh.append([x + lx * 0.35 * (1.0 - Px.hypot(x, y) / R), y + ly * 0.35 * (1.0 - Px.hypot(x, y) / R)])
		for k in range(1, sh.size()):
			g.line(sh[k - 1][0], sh[k - 1][1], sh[k][0], sh[k][1], VEIN if k < 2 else Px.mix(VEIN, C[3], 0.45))
	# the iris, foreshortened as it turns away, a dark ring, a green that brightens toward the pupil
	var off := Px.hypot(lx, ly)
	var fx := 1.0 - 0.32 * (absf(lx) / R) ** 1.4 * 3.0
	var fy := 1.0 - 0.32 * (absf(ly) / R) ** 1.4 * 3.0
	var ir := 6.4
	var pr := 2.0 + 0.4 * sin((t / D) * TAU * 2.0)
	g.shade(lx - ir - 1.0, ly - ir - 1.0, lx + ir + 1.0, ly + ir + 1.0, func(x, y):
		var dx: float = (x - lx) / (ir * fx)
		var dy: float = (y - ly) / (ir * fy)
		var d := Px.hypot(dx, dy)
		if d > 1.0 or Px.hypot(x, y) > R - 0.5:
			return 0
		var pd := Px.hypot((x - lx) / fx, (y - ly) / fy)
		if pd < pr:
			return C[0]
		if d > 0.86:
			return I[0]
		var ang := atan2(dy, dx)
		var streak := sin(ang * 9.0 + d * 4.0) > 0.5
		if d < 0.5:
			return I[4] if streak else I[3]
		if d < 0.7:
			return I[3] if streak else I[2]
		return I[2] if streak else I[1])
	# a fixed glint from the light, whichever way it looks
	if L < 0.5:
		g.setc(-4, -5, C[5])
		g.setc(-3, -5, C[5])
		g.setc(-4, -4, C[5])
		g.setc(1, -2, C[5])
	# the lids: fleshy shells over the top and bottom, lit like the ball they wrap, the upper one sweeping down to blink
	var up := Px.lerp(-R + 3.0, R * 0.42, L)
	var dn := Px.lerp(R - 2.2, R * 0.42, L)
	var flit := func(x: float, y: float, k: float) -> bool:
		return Px.hypot(-4.0 + (x + 4.0) / k, -5.0 + (y + 5.0) / k) <= R + 0.6
	g.shade(-R - 1.0, -R - 1.0, R + 1.0, R + 1.0, func(x, y):
		var d := Px.hypot(x, y)
		if d > R + 0.6:
			return 0
		var ue: float = up + 1.8 * (x / R) ** 2
		var de: float = dn - 1.4 * (x / R) ** 2
		var tone: int = Fl[1] if not (Px.hypot(x + 2.0, y + 2.2) <= R + 0.6) else (Fl[4] if flit.call(x, y, 0.55) else (Fl[3] if flit.call(x, y, 0.85) else Fl[2]))
		if y < ue:
			return Fl[0] if y > ue - 1.2 else tone
		if y > de:
			return Fl[0] if y < de + 1.1 else (Fl[3] if tone == Fl[4] else tone)
		return 0)
	g.outline(C[0])


static func draw(p: Px.Painter, time: float, o: Dictionary) -> void:
	var t := Lib.shift(time, D, o.seed)
	var C := Px.fit(o.palette, 6)
	var Fl := Px.fit(o.flesh, 5)
	var I := Px.fit(o.iris, 5)
	var S := at(t, o.hover)
	# the optic nerve hangs from the back, trailing the bob a beat behind: one tube, lit down its left side
	var ng: Lib.Grid = NERVE.clear()
	var s := 0.0
	while s <= 20.0:
		var B := at(t - s * 0.035, o.hover)
		var sw := 2.6 * (s / 20.0) ** 1.3 * sin((t / D) * TAU * 2.0 - s * 0.16)
		var r := Px.lerp(2.0, 0.6, s / 20.0)
		var cx: float = B.x + 1.0 + sw
		var cy: float = B.y + R - 2.0 + s
		ng.shade(cx - r - 1.0, cy - 1.0, cx + r + 1.0, cy + 1.0, func(x, y):
			var v: float = (x - cx) / maxf(0.6, r)
			if absf(v) > 1.0 or absf(y - cy) > 0.5:
				return 0
			return Fl[4] if v < -0.35 else (Fl[3] if v < 0.4 else Fl[2]))
		s += 0.5
	ng.outline(Fl[0])
	ng.draw(p)
	var g := GRID
	eye(g, C, Fl, I, t, o.seed)
	g.draw(p, 1.0, S.x, S.y)
	# the iris glows, an eerie halo round the whole eye, motes circling it
	var lxy := look(t)
	var lx: float = lxy[0]
	var ly: float = lxy[1]
	var snap := -INF
	for q in LOOKS:
		var t0: float = q[0]
		snap = maxf(snap, maxf(0.0, 1.0 - absf(Px.wrap(t - t0 + D / 2.0, D) - D / 2.0) / 0.2))
	var open := 1.0 - lid(t)
	p.glow(S.x + lx, S.y + ly, 15.0, I[3], (0.5 + 0.3 * snap) * open)
	p.glow(S.x + lx, S.y + ly, 5.0, I[4], 0.4 * open)
	p.glow(S.x, S.y, 50.0, I[1], 0.3)
	# motes of green light wheel round it on a tilted orbit, trailing short streaks
	for i in 8:
		var sp := (1 if i % 2 else -1) * (1 if i % 3 else 2)
		var a0 := (i * TAU) / 8.0
		var rr := 19 + (i % 3) * 2
		var prev: Variant = null
		var k := 5
		while k >= 0:
			var a := (t / D) * TAU * sp + a0 - sp * k * 0.035
			var z := sin(a)
			var x: float = S.x + cos(a) * rr
			var y: float = S.y + z * 5.0 - cos(a) * 3.0
			if z < 0.0 and Px.hypot(x - S.x, y - S.y) < R + 1.0:
				prev = null
				k -= 1
				continue
			if prev != null and k > 0:
				p.line(prev[0], prev[1], x, y, I[2], 0.4 + (5 - k) * 0.12)
			if k == 0:
				p.px(x, y, I[4] if z > 0.0 else I[3])
				p.glow(x, y, 5.0, I[3], 0.45)
			prev = [x, y]
			k -= 1


static func drawBack(p: Px.Painter, time: float, o: Dictionary) -> void:
	var t := Lib.shift(time, D, o.seed)
	var I := Px.fit(o.iris, 5)
	var S := at(t, o.hover)
	Lib.shadow(p, S.x, 0.0, 10.0, 1.5, Px.hex("#0d0a12"), 0.5)
	for x in range(-26, 27, 6):
		p.glow(S.x + x, -1.0, 18.0, I[2], 0.15 * (1.0 - absf(x) / 34.0))
