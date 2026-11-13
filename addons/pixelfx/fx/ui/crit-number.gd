# port-of: src/fx/ui/crit-number.js@4c6978bf8a288cb492c58d0680ace623d9d8d567
extends "../../core/effect.gd"

const Px := preload("../../core/px.gd")
const Lib := preload("_lib.gd")
const P := Px.P
const B := Px.B
const WHITE := Px.WHITE

static var meta := {
	"name": "Crit number",
	"desc": "CRIT 128! slams in huge and white over a jagged starburst with a hard shake and speed lines, cools to fire, holds with a shine, then pops into sparks.",
	"tags": ["ui", "critical", "damage", "number", "combat", "text", "one-shot"],
	"size": [152, 120],
	"origin": [76, 60],
	"duration": 1.5,
	"loop": false,
	"fps": 30,
	"bg": "dark",
	"options": {"palette": ["#2a0710", "#5e0f16", "#a3191c", "#e0401c", "#ff7b22", "#ffb93b", "#ffe68a", "#ffffff"], "text": "128!", "label": "CRIT", "seed": 3},
}

const FOLD := 0.92
const TAGOUT := 0.98
const POP := 1.06
const SX := 1.3
const NS := 4.0
const NY := 5.0


# the jagged starburst: a spiky polygon with a dark rim, a bright inner contour, bands that cool from the
# white-hot middle out, and spokes of light running to every tip. heat 1 is white all through.
static func starburst(p: Px.Painter, C: Array, cx: float, cy: float, R: float, rot: float, tips: Array, heat: float, boil: float, a: float = 1.0) -> void:
	if R < 2.0 or a <= 0.0:
		return
	var n := tips.size()
	var V := []
	for i in n * 2:
		var an := rot + (i * PI) / n
		var r: float = R * ((0.6 + tips[i >> 1].dip) if i % 2 else tips[i >> 1].len * (1.0 + 0.14 * (Px.rand(boil, i) - 0.5)))
		V.append([cos(an) * r, sin(an) * r, an])
	var step := PI / n
	# (the vertices as flat lists and the color steps, made once: the shader below runs for every pixel)
	var nV := V.size()
	var VX := PackedFloat64Array()
	var VY := PackedFloat64Array()
	for v: Array in V:
		VX.append(v[0])
		VY.append(v[1])
	var STEPS := [WHITE, C[6], C[5], C[4], C[3], C[2]]
	var M := R * 1.15 + 2.0
	p.shade(cx - M * SX, cy - M, cx + M * SX, cy + M, func(x: float, y: float, o):
		var dx := (x - cx) / SX
		var dy := y - cy
		var d := Px.hypot(dx, dy)
		if d < 0.01:
			return WHITE
		# edge(dx / d, dy / d): where the ray from the middle through (dx, dy) leaves the polygon: the vertices sit
		# at even angles, so the ray's angle names the one edge it can cross
		var ux := dx / d
		var uy := dy / d
		var ea := atan2(uy, ux) - rot
		ea -= floorf(ea / TAU) * TAU
		var ei := mini(nV - 1, floori(ea / step))
		var ej := (ei + 1) % nV
		var x0 := VX[ei]
		var y0 := VY[ei]
		var ex := VX[ej] - x0
		var ey := VY[ej] - y0
		var den := ux * ey - uy * ex
		var L := Px.hypot(x0, y0) if absf(den) < 1e-9 else (x0 * ey - y0 * ex) / den
		var gap := (L - d) * (1.0 + 0.3 * absf(dx / d))
		var q := d / L
		if gap < 0.0:
			return null
		o.a = a
		if heat > 0.85:
			return C[6] if gap < 1.0 else WHITE
		# a dark edge, a glowing rim inside it, then a middle that deepens to dark red for the number to stand on
		if gap < 1.0:
			return C[1]
		if gap < 2.2:
			return WHITE if heat > 0.3 else C[6]
		if gap < 3.4:
			return C[6] if heat > 0.3 else C[5]
		if gap >= 6.0 and gap < 7.0:
			return WHITE if heat > 0.5 else C[4]
		# spokes: a line of light from the middle out to each tip
		var an := atan2(dy, dx) - rot
		var sp := absf(fmod((an / TAU) * n + 0.5, 1.0) - 0.5) * (TAU / n) * d
		if sp < 0.6 and q > 0.25:
			return WHITE if heat > 0.5 else (C[5] if q > 0.6 else C[4])
		var i := Px.roundi((3.0 if q > 0.72 else (4.0 if q > 0.45 else 5.0)) - heat * 5.0)
		return WHITE if i <= 0 else STEPS[i])


# the CRIT tag: a leaning dark plate with a lit top edge
static func tag(p: Px.Painter, C: Variant, x: float, y: float, w: float, h: float, lean: float) -> void:
	p.shade(x - 1.0, y - 1.0, x + w + lean + 1.0, y + h + 1.0, func(px: float, py: float):
		var lx := px - x - lean * ((y + h - py) / h)
		if py < y or py > y + h or lx < 0.0 or lx > w:
			return null
		if lx < 1.0 or lx > w - 1.0 or py < y + 1.0 or py > y + h - 1.0:
			return C[0]
		return C[4] if py < y + 2.0 else (C[3] if py < y + h * 0.55 else C[2]))


# speed lines thrown out round the burst
static func speedLines(p: Px.Painter, C: Array, t: float, lines: Array) -> void:
	var k := t / 0.24
	if k <= 0.0 or k >= 1.0:
		return
	for l: Dictionary in lines:
		var r0: float = l.r * (1.0 + 0.5 * Px.Ease.outExpo(k))
		var r1: float = r0 + l.len * (1.0 - k) + 2.0
		var ca: float = cos(l.a) * 1.2
		var sa: float = sin(l.a) * 0.92
		p.line(ca * r0, sa * r0, ca * r1, sa * r1, func(u: float): return WHITE if (u > 0.5 or k < 0.3) else C[6])


var o: Dictionary
var C: Array
var R: Px.Rng
var SHADOW: int
var ps: Px.Particles
var bits: Px.Bits
var lights: Px.Lights
var num: Dictionary
var lab: Dictionary
var tips: Array
var lines: Array
var end: float
var t := 0.0
var slammed := false
var stamped := false
var popped := false
var tagGone := false


func create(o_: Dictionary) -> void:
	o = o_
	C = Px.fit(o.palette, 8)
	R = Px.Rng.new(o.seed)
	SHADOW = Px.scale(C[0], 0.5)
	ps = Px.Particles.new({"rng": R, "sparks": [C[7], C[6], C[5], C[3]]})
	bits = Px.Bits.new()
	lights = Px.Lights.new()
	num = Lib.spell(o.text)
	lab = Lib.spell(o.label, "mini")
	tips = Px.arr(13, func(_i): return {"len": R.range(0.86, 1.12), "dip": R.range(-0.06, 0.06)})
	lines = Px.arr(18, func(i: int): return {"a": (i / 18.0) * TAU + R.range(-0.1, 0.1), "r": R.range(31.0, 34.0), "len": R.range(8.0, 15.0)})
	end = meta.duration - 0.05


# how long a spark launched at v px/s may live before its drag carries it d px (so none leaves the canvas)
static func reach(v: float, d: float) -> float:
	return 9.0 if v <= d * 2.2 else -log(1.0 - (d * 2.2) / v) / 2.2


func spawnStar(x: float, y: float, vx: float, vy: float, life: float, c: Variant, size: float) -> void:
	ps.spawn(P.STAR, x, y, vx, vy, minf(life, end - t), c, size)


# the number's size: huge for the first frame, then a stiff spring down to 3 px a pixel
static func sizeAt(tt: float) -> float:
	return NS + 3.0 * exp(-tt * 26.0) * cos(tt * 38.0)


func update(dt: float) -> void:
	t += dt
	if not slammed:
		slammed = true
		lights.add(0.0, 0.0, 70.0, WHITE, 0.9, 0.16)
		lights.add(0.0, 0.0, 60.0, C[4], 0.45, 0.5)
		for i in 30:
			var an := R.range(0.0, TAU)
			var sp := R.range(140.0, 300.0)
			ps.spawn(P.SPARK, cos(an) * 8.0, sin(an) * 6.0, cos(an) * sp * 1.15, sin(an) * sp - 40.0, minf(R.range(0.12, 0.32), reach(sp * 1.15, 40.0)))
		for i in 10:
			var an := R.range(0.0, TAU)
			var sp := R.range(90.0, 170.0)
			bits.add({"kind": B.SHARD, "x": cos(an) * 10.0, "y": sin(an) * 7.0, "vx": cos(an) * sp * 1.15, "vy": sin(an) * sp - 60.0, "g": 0.35, "drag": 1.6, "life": minf(R.range(0.3, 0.5), end - t), "a": R.range(0.0, TAU), "va": R.range(-24.0, 24.0), "s": R.range(2.0, 3.5), "c": R.pick([C[7], C[6], C[5]])})
	# the label stamps down a beat later
	if not stamped and t >= 0.09:
		stamped = true
		lights.add(-4.0, -20.0, 30.0, C[6], 0.5, 0.2)
		for i in 6:
			ps.spawn(P.STAR, -4.0 + R.range(-16.0, 16.0), -20.0 + R.range(-4.0, 4.0), R.range(-40.0, 40.0), R.range(-30.0, 10.0), R.range(0.2, 0.4), C[6], R.range(0.5, 1.4))
	# the tag bursts into sparkles as it goes
	if not tagGone and t >= TAGOUT:
		tagGone = true
		for i in 6:
			spawnStar(-10.0 + R.range(-16.0, 16.0), -14.0 + R.range(-5.0, 5.0), R.range(-50.0, 50.0), -R.range(10.0, 60.0), R.range(0.25, 0.4), R.pick([C[7], C[6]]), 0.6 if i else 1.6)
	# the burst crackles: sparks spit from its tips
	if t > 0.3 and t < FOLD - 0.1 and R.chance(0.07):
		var an := R.range(0.0, TAU)
		var sp := R.range(70.0, 150.0)
		ps.spawn(P.SPARK, cos(an) * 30.0 * SX, sin(an) * 30.0, cos(an) * sp, sin(an) * sp - 30.0, minf(R.range(0.12, 0.26), reach(sp, 14.0)))
	# embers lift off the burst while it holds
	if t > 0.12 and t < FOLD and R.chance(0.16):
		var an := R.range(0.0, TAU)
		var r := R.range(14.0, 28.0)
		ps.spawn(P.EMBER, cos(an) * r * SX, sin(an) * r, R.range(-10.0, 10.0), -R.range(15.0, 40.0), minf(R.range(0.5, 0.9), end - t), C[5], R.range(1.0, 2.0))
	if not popped and t >= POP + 0.05:
		popped = true
		lights.add(0.0, 0.0, 44.0, C[6], 0.7, 0.25)
		for i in 14:
			var an := (i / 14.0) * TAU + R.range(-0.15, 0.15)
			var sp := R.range(60.0, 130.0)
			ps.spawn(P.STAR, cos(an) * 10.0 * SX, sin(an) * 7.0, cos(an) * sp * SX, sin(an) * sp - 10.0, minf(R.range(0.3, 0.42), end - t), R.pick([C[7], C[6], C[5]]), 0.6 if i % 3 else R.range(1.3, 2.2))
		for i in 8:
			var an := R.range(0.0, TAU)
			var sp := R.range(120.0, 240.0)
			ps.spawn(P.SPARK, cos(an) * 6.0, sin(an) * 4.0, cos(an) * sp, sin(an) * sp - 30.0, minf(minf(R.range(0.15, 0.3), end - t), reach(sp, 40.0)))
	ps.update(dt)
	bits.update(dt)
	lights.update(dt)


func draw(p: Px.Painter) -> void:
	var sxy := Lib.shake(t, 4.0, 0.0, 0.32, o.seed)
	var sx: float = sxy[0]
	var sy: float = sxy[1]
	var lxy := Lib.shake(t, 2.0, 0.09, 0.15, o.seed + 3.0)
	var lx: float = lxy[0]
	var ly: float = lxy[1]
	# the burst: white on the slam, cooling; it breathes while it holds, then folds away
	var grow := 1.25 if t < 0.04 else 1.0 + 0.1 * exp(-(t - 0.04) * 14.0)
	var fold := 1.0 - Px.Ease.inBack(Px.seg(t, FOLD - 0.12, FOLD), 2.4)
	var heat := 1.0 if t < 0.035 else Px.clamp(1.0 - (t - 0.035) / 0.12)
	var breathe := 1.0 + 0.04 * sin(t * 16.0)
	# it boils: the spikes re-roll a little every few frames
	if fold > 0.02:
		starburst(p, C, sx, sy, 31.0 * grow * fold * breathe, -PI / 2.0 + 0.25 * t, tips, heat, 0.0 if t < 0.2 else floorf(t * 10.0))
	speedLines(p, C, t, lines)
	# the ring the slam throws out
	var rk := t / 0.26
	var rr := 30.0 + 22.0 * Px.Ease.outCubic(rk)
	if rk > 0.0 and rk < 1.0:
		p.ellipse(0.0, 0.0, rr * SX, rr, WHITE if rk < 0.35 else C[6], func(d: float): return 1.2 - rk if d > 1.0 - 1.6 / rr else 0.0)
	bits.draw(p)
	ps.draw(p)
	# the number: slams in huge and white, settles with a spring; a shine runs over it; it pops at the end
	var s := sizeAt(t)
	var sxN := s
	var syN := s
	var flash := 1.0 if t < 0.035 else (0.5 if t < 0.07 else 0.0)
	var pu := (t - POP) / 0.05
	if pu >= 1.0:
		# gone: a ring where it was
		var k := (t - POP - 0.05) / 0.22
		if k > 0.0 and k < 1.0:
			p.ellipse(0.0, 0.0, (6.0 + 22.0 * Px.Ease.outCubic(k)) * SX, 6.0 + 22.0 * Px.Ease.outCubic(k), WHITE if k < 0.4 else C[6], func(d: float): return 1.3 - k if d > 1.0 - 1.5 / (6.0 + 22.0 * Px.Ease.outCubic(k)) else 0.0)
	else:
		var sq := Px.seg(t, POP - 0.07, POP)
		if sq > 0.0 and pu <= 0.0:
			sxN = NS * (1.0 + 0.14 * sq)
			syN = NS * (1.0 - 0.12 * sq)
		if pu > 0.0:
			sxN = NS * (1.0 + 0.25 * pu)
			syN = sxN
			flash = 1.0
		var W: float = num.w * sxN
		var H := 7.0 * syN
		var x0 := sx - W / 2.0 - 3.0
		var y0 := sy + NY - H / 2.0 - 3.0 * Px.smooth(0.15, FOLD, t)
		var items := []
		for L: Dictionary in num.letters:
			if L.g != null:
				items.append({"g": L.g, "x": x0 + L.x * sxN, "y": y0, "sx": sxN, "sy": syN, "slant": 1.0, "flash": flash})
		var sh := Px.seg(t, 0.36, 0.6)
		var shine: Variant = x0 - 10.0 + (W + 26.0) * Px.Ease.inOutSine(sh) if (sh > 0.0 and sh < 1.0) else null
		Lib.drawWord(p, items, {"fill": [C[5], C[6], C[6], C[7]], "edge": WHITE, "under": C[4], "outline": C[0], "ow": 2, "shadow": SHADOW, "shine": shine, "shineY": y0, "glint": C[5]})
		if shine != null and shine > x0 and shine < x0 + W:
			p.glowLine(shine, y0, shine + 0.6 * H, y0 + H, 8.0, C[6], 0.3)
		# the label stamps down on top, a size too big for a frame
		var lk := t - 0.06
		var lo := Px.seg(t, TAGOUT - 0.05, TAGOUT)
		if lk > 0.0 and t < TAGOUT:
			var ls := 3.0 if lk < 0.035 else (1.8 if lk < 0.07 else 2.0 * (1.0 + 0.15 * lo))
			var LW: float = lab.w * ls
			var lh := 5.0 * ls
			var lxo := sx + lx - 8.0 - LW / 2.0
			var lyo := y0 - 3.0 - lh + ly - 2.0 * lo
			if lo > 0.5:
				tag(p, {0: WHITE, 2: WHITE, 3: WHITE, 4: WHITE}, lxo - 4.0, lyo - 3.0, LW + 8.0, lh + 5.0, 3.0)
			else:
				tag(p, C, lxo - 4.0, lyo - 3.0, LW + 8.0, lh + 5.0, 3.0)
			var lit := []
			for L: Dictionary in lab.letters:
				if L.g != null:
					lit.append({"g": L.g, "x": lxo + 1.0 + L.x * ls, "y": lyo, "sx": ls, "sy": ls, "slant": 0.5, "flash": 1.0 if lk < 0.035 else 0.0})
			Lib.drawWord(p, lit, {"fill": [C[6], C[7], C[7]], "edge": WHITE, "under": C[5], "outline": 0, "shadow": C[1]})
		# a glint on the number's corner after the shine
		var g := (t - 0.6) / 0.24
		if g > 0.0 and g < 1.0:
			Px.sparkle(p, x0 + W - 2.0, y0 + 1.0, 6.0 * sin(g * PI), C[6], C[5], 0.6)
	# light: the white flash of the slam, then a hot glow that pulses while it holds
	var hold := Px.smooth(0.0, 0.1, t) * (1.0 - Px.smooth(FOLD - 0.1, POP + 0.1, t))
	p.glow(sx, sy, 56.0, C[4], 0.14 * hold * (1.0 + 0.2 * sin(t * 16.0)))
	if t < 0.12:
		p.glow(0.0, 0.0, 64.0, WHITE, 0.8 * (1.0 - t / 0.12))
	lights.draw(p)
