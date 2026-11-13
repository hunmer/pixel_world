# port-of: src/fx/ui/countdown.js@6cb827c32e483e0d1eb69e428d59f48c0a43e64c
extends "../../core/effect.gd"

const Px := preload("../../core/px.gd")
const Lib := preload("_lib.gd")
const P := Px.P
const WHITE := Px.WHITE

static var meta := {
	"name": "Countdown",
	"desc": "3, 2, 1 slam into a timer ring that drains like a burning fuse, throwing sparks; then GO! bursts out as the ring blows into a shockwave with rays.",
	"tags": ["ui", "countdown", "start", "timer", "text", "one-shot"],
	"size": [152, 136],
	"origin": [76, 68],
	"duration": 3.1,
	"loop": false,
	"fps": 30,
	"bg": "dark",
	"options": {
		"palette": ["#0a1030", "#142a66", "#1f4fae", "#2f86e6", "#5cc4ff", "#a8e8ff", "#e6fbff", "#ffffff"],
		"go": ["#0b2410", "#16501c", "#22882a", "#3cc23a", "#7ee84c", "#c4ff8a", "#f0ffd6", "#ffffff"],
		"from": 3,
		"word": "GO!",
		"seed": 5,
	},
}

const STEP := 0.62
const R := 30.0
const TOP := -PI / 2.0


# the timer: a dark socket, ticks round it, and the lit arc from the burning head round to the top
static func timer(p: Px.Painter, C: Array, x: float, y: float, f: float, flash: bool, t: float) -> float:
	p.ring(x, y, R + 4.0, 8.0, func(v: float): return C[0] if (v < 0.13 or v > 0.87) else C[1])
	# a fine dotted dial inside the track, turning
	for j in 40:
		var an := (j / 40.0) * TAU + t * 0.6
		p.dot(x + cos(an) * (R - 6.0), y + sin(an) * (R - 6.0), C[2] if j % 5 else C[4], 1.0)
	var head := TOP + TAU * (1.0 - f)
	for i in 12:
		var an := TOP + (i * TAU) / 12.0
		var lit := an >= head - 1e-6 or f >= 0.999
		var near := absf(an - head) < 0.2 and f < 0.999
		var ca := cos(an)
		var sa := sin(an)
		p.line(x + ca * (R + 6.0), y + sa * (R + 6.0), x + ca * (R + 8.0), y + sa * (R + 8.0), WHITE if (flash or near) else (C[5] if lit else C[2]))
	if f <= 0.002:
		return head
	p.arc(x, y, R + 2.0, 5.0, head, TOP + TAU, func(u: float, v: float):
		var d := u * TAU * f
		if flash or d < 0.1:
			return WHITE
		if d < 0.32:
			return WHITE if v > 0.5 else C[6]
		return C[6] if v > 0.75 else (C[5] if v > 0.4 else (C[4] if v > 0.15 else C[3])))
	# light runs round the lit arc, hottest at the head
	var an := head + 0.25
	while an < TOP + TAU:
		p.glow(x + cos(an) * (R - 0.5), y + sin(an) * (R - 0.5), 9.0, C[4], 0.12)
		an += 0.55
	var hx := x + cos(head) * (R - 0.5)
	var hy := y + sin(head) * (R - 0.5)
	p.glow(hx, hy, 14.0, C[5], 0.5)
	if not flash:
		Px.sparkle(p, hx, hy, 2.0 + 1.5 * (0.5 + 0.5 * sin(t * 40.0)), C[6], C[5], 0.4)
	return head


var o: Dictionary
var C: Array
var G: Array
var Rg: Px.Rng
var n: float
var ps: Px.Particles
var gs: Px.Particles
var lights: Px.Lights
var GO: float
var OUT: float
var end: float
var digits: Array
var word: Dictionary
var rays: Array
var t := 0.0
var beat := -1.0
var went := false
var popped := false


func create(o_: Dictionary) -> void:
	o = o_
	C = Px.fit(o.palette, 8)
	G = Px.fit(o.go, 8)
	Rg = Px.Rng.new(o.seed)
	n = Px.clamp(Px.round(o.from), 1.0, 3.0)
	ps = Px.Particles.new({"rng": Rg, "sparks": [C[7], C[6], C[5], C[3]]})
	gs = Px.Particles.new({"rng": Rg, "sparks": [G[7], G[6], G[5], G[3]]})
	lights = Px.Lights.new()
	GO = n * STEP
	OUT = GO + 0.78
	end = meta.duration - 0.05
	digits = Px.arr(n, func(i: int): return Lib.spell(str(int(n - i))))
	word = Lib.spell(o.word)
	rays = Px.arr(18, func(i: int): return {"a": (i / 18.0) * TAU + Rg.range(-0.06, 0.06), "L": Rg.range(10.0, 16.0) if i % 2 else Rg.range(22.0, 30.0)})


static func sizeAt(u: float, base: float, big: float) -> float:
	return base + big * exp(-u * 26.0) * cos(u * 38.0)


static func reach(v: float, d: float) -> float:
	return 9.0 if v <= d * 2.2 else -log(1.0 - (d * 2.2) / v) / 2.2


func update(dt: float) -> void:
	t += dt
	var i := floorf(t / STEP)
	# each number slams in: the ring refills white and throws a ring of sparks
	if t < GO and i != beat:
		beat = i
		lights.add(0.0, 0.0, 54.0, C[5], 0.6, 0.35)
		for j in 14:
			var an := (j / 14.0) * TAU + Rg.range(-0.1, 0.1)
			var sp := Rg.range(90.0, 200.0)
			ps.spawn(P.SPARK, cos(an) * (R + 2.0), sin(an) * (R + 2.0), cos(an) * sp, sin(an) * sp, minf(Rg.range(0.12, 0.3), reach(sp, 26.0)))
	# the burning head of the arc spits sparks as it runs
	if t < GO:
		var k := fmod(t, STEP) / STEP
		var f := 1.0 - Px.seg(k, 0.06, 0.97)
		var head := TOP + TAU * (1.0 - f)
		if f > 0.01 and f < 0.99 and Rg.chance(0.7):
			var hx := cos(head) * R
			var hy := sin(head) * R
			var tx := -sin(head)
			var ty := cos(head)
			var out := Rg.range(-0.4, 1.0)
			var sp := Rg.range(60.0, 150.0)
			ps.spawn(P.SPARK, hx, hy, (-tx * 0.8 + cos(head) * out) * sp, (-ty * 0.8 + sin(head) * out) * sp - 20.0, Rg.range(0.12, 0.28))
			# and leaves cinders drifting off the burnt-out track behind it
			if Rg.chance(0.15):
				ps.spawn(P.EMBER, hx, hy, cos(head) * Rg.range(5.0, 20.0), sin(head) * Rg.range(5.0, 20.0), Rg.range(0.4, 0.8), C[5], 1.0)
	# GO!: the ring blows out, sparks and stars everywhere
	if not went and t >= GO:
		went = true
		lights.add(0.0, 0.0, 70.0, WHITE, 0.9, 0.18)
		lights.add(0.0, 0.0, 64.0, G[5], 0.7, 0.8)
		for j in 36:
			var an := Rg.range(0.0, TAU)
			var sp := Rg.range(120.0, 300.0)
			gs.spawn(P.SPARK, cos(an) * R, sin(an) * R, cos(an) * sp, sin(an) * sp - 40.0, minf(Rg.range(0.18, 0.36), reach(sp, 24.0)))
		for j in 18:
			var an := Rg.range(0.0, TAU)
			var sp := Rg.range(30.0, 80.0)
			var r := Rg.range(10.0, 28.0)
			gs.spawn(P.STAR, cos(an) * r, sin(an) * r, cos(an) * sp, sin(an) * sp - 10.0, Rg.range(0.5, 1.0), Rg.pick([G[7], G[6], G[5]]), Rg.range(1.5, 2.5) if Rg.chance(0.4) else 0.6)
	# it twinkles while it holds
	if t > GO + 0.2 and t < OUT - 0.1 and Rg.chance(0.12):
		var an := Rg.range(0.0, TAU)
		var r := Rg.range(30.0, 46.0)
		gs.spawn(P.STAR, cos(an) * r, sin(an) * r * 0.8, 0.0, -Rg.range(4.0, 12.0), Rg.range(0.3, 0.6), Rg.pick([G[7], G[6]]), 1.6 if Rg.chance(0.3) else 0.6)
	if not popped and t >= OUT + 0.05:
		popped = true
		lights.add(0.0, 0.0, 40.0, G[6], 0.6, 0.25)
		for j in 14:
			var an := (j / 14.0) * TAU + Rg.range(-0.15, 0.15)
			var sp := Rg.range(60.0, 130.0)
			gs.spawn(P.STAR, cos(an) * 12.0, sin(an) * 8.0, cos(an) * sp, sin(an) * sp * 0.8 - 10.0, minf(Rg.range(0.3, 0.45), end - t), Rg.pick([G[7], G[6], G[5]]), 0.6 if j % 3 else Rg.range(1.3, 2.0))
	ps.update(dt)
	gs.update(dt)
	lights.update(dt)


func draw(p: Px.Painter) -> void:
	if t < GO:
		var i := floorf(t / STEP)
		var u := t - i * STEP
		var k := u / STEP
		var sxy := Lib.shake(t, 3.0, i * STEP, 0.22, o.seed + i)
		var sx: float = sxy[0]
		var sy: float = sxy[1]
		var f := 1.0 - Px.seg(k, 0.06, 0.97)
		var flash := u < 0.07
		# a shock ring off each slam
		var rk := u / 0.3
		if rk < 1.0:
			p.ring(sx, sy, R + 6.0 + 22.0 * Px.Ease.outCubic(rk), 1.5 * (1.0 - rk) + 1.0, WHITE if rk < 0.3 else C[5], 1.3 * (1.0 - rk))
		timer(p, C, sx, sy, f, flash, t)
		# the slam's white-hot frame fills the ring
		if u < 0.035:
			p.circle(sx, sy, R - 3.0, WHITE)
		elif u < 0.07:
			p.ring(sx, sy, R - 3.0, 3.0, C[6])
		# the number: huge and white for a frame, then a stiff spring down to size
		var s := sizeAt(u, 5.0, 2.0)
		var d: Dictionary = digits[int(i)]
		var W: float = d.w * s
		var H := 7.0 * s
		var x0 := sx - W / 2.0
		var y0 := sy - H / 2.0
		var items := []
		for L: Dictionary in d.letters:
			if L.g != null:
				items.append({"g": L.g, "x": x0 + L.x * s, "y": y0, "sx": s, "sy": s, "flash": 1.0 if u < 0.035 else (0.4 if u < 0.07 else 0.0)})
		Lib.drawWord(p, items, {"fill": [C[4], C[5], C[6], C[7]], "edge": WHITE, "under": C[3], "outline": C[0], "ow": 2, "shadow": Px.scale(C[0], 0.5)})
		p.glow(sx, sy, 30.0, C[4], 0.22 + (0.6 * (1.0 - u / 0.12) if u < 0.12 else 0.0))
		p.glow(sx, sy, R + 8.0, C[3], 0.2 * (1.0 - k) + 0.08)
	else:
		var u := t - GO
		var sxy := Lib.shake(t, 4.0, GO, 0.3, o.seed + 9.0)
		var sx: float = sxy[0]
		var sy: float = sxy[1]
		# the ring blows out into a shockwave
		var bk := u / 0.4
		if bk < 1.0:
			var r := R + 4.0 + 30.0 * Px.Ease.outCubic(bk)
			var w := maxf(1.0, 7.0 * (1.0 - bk))
			p.ring(0.0, 0.0, r, w, func(v: float): return WHITE if (bk < 0.2 or v > 0.6) else G[6], 1.4 * (1.0 - bk))
			p.glowRing(0.0, 0.0, r - w / 2.0, 8.0, G[5], 0.5 * (1.0 - bk))
		var ik := (u - 0.05) / 0.3
		if ik > 0.0 and ik < 1.0:
			p.ring(0.0, 0.0, R + 22.0 * Px.Ease.outCubic(ik), 1.0, G[5], 1.2 * (1.0 - ik))
		# rays: shoot out from just outside the word, turn slowly, draw back in
		var rk := Px.Ease.outExpo(Px.clamp(u / 0.18)) * (1.0 - Px.Ease.inQuad(Px.seg(t, OUT - 0.25, OUT + 0.05)))
		for ry: Dictionary in rays:
			if rk <= 0.02:
				break
			var an: float = ry.a + u * 0.35
			var ca := cos(an)
			var sa := sin(an)
			var r0 := 1.0 / sqrt(pow(ca / 40.0, 2.0) + pow(sa / 23.0, 2.0)) + 3.0 * rk
			var r1: float = r0 + ry.L * 0.7 * rk
			p.line(ca * r0, sa * r0, ca * r1, sa * r1, func(q: float): return WHITE if q < 0.3 else (G[6] if q < 0.65 else G[5]), func(q: float): return 1.3 if q < 0.6 else (1.3 * (1.0 - q)) / 0.4)
		# GO!: slams in bigger than the numbers, throbs while it holds, then pops
		var pu := (t - OUT) / 0.06
		if pu < 1.0:
			var s := sizeAt(u, 5.0, 3.5)
			var flash := 1.0 if u < 0.035 else (0.4 if u < 0.07 else 0.0)
			var throb := maxf(0.0, sin((u - 0.25) * 9.0)) * Px.smooth(0.25, 0.35, u)
			if pu > 0.0:
				s = 5.0 * (1.0 + 0.25 * pu)
				flash = 1.0
			var W: float = word.w * s
			var H := 7.0 * s
			var x0 := sx - W / 2.0
			var y0 := sy - H / 2.0
			var items := []
			for L: Dictionary in word.letters:
				if L.g != null:
					items.append({"g": L.g, "x": x0 + L.x * s, "y": y0, "sx": s, "sy": s, "slant": 1.0, "flash": flash})
			var sh := Px.seg(u, 0.32, 0.56)
			var shine: Variant = x0 - 8.0 + (W + 22.0) * Px.Ease.inOutSine(sh) if (sh > 0.0 and sh < 1.0) else null
			Lib.drawWord(p, items, {"fill": [G[4], G[5], G[6], G[7]], "edge": WHITE, "under": G[3], "outline": G[0], "ow": 2, "shadow": Px.scale(G[0], 0.5), "shine": shine, "shineY": y0, "glint": G[6]})
			p.glow(sx, sy, 46.0, G[5], 0.25 + 0.15 * throb + (0.7 * (1.0 - u / 0.12) if u < 0.12 else 0.0))
		else:
			var k := (t - OUT - 0.06) / 0.22
			if k > 0.0 and k < 1.0:
				p.ring(0.0, 0.0, 8.0 + 26.0 * Px.Ease.outCubic(k), 1.0, WHITE if k < 0.4 else G[6], 1.3 * (1.0 - k))
	ps.draw(p)
	gs.draw(p)
	lights.draw(p)
