# The streaks pulled in, the rings and lights at the burst and the collapse pop are adapted from Sprite
# Fusion's open-source black-hole (https://www.spritefusion.com/pixel-art-vfx/black-hole),
# MIT License, Copyright (c) 2026 Hugo Duprez.
# port-of: src/fx/spawn/spawn-portal.js@c7130998e522af99d0b88316dfd4d742e9c3177a
extends "../../core/effect.gd"

const Px := preload("../../core/px.gd")
const P := Px.P
const PF := Px.PF
const B := Px.B
const WHITE := Px.WHITE

static var meta := {
	"name": "Spawn portal",
	"desc": "A rift tears open on the floor and swirls, belches violet smoke and sparks, spits a fountain of wisps up out of itself, then twists shut with a pop.",
	"tags": ["spawn", "portal", "summon", "rift", "arcane", "smoke", "ground", "one-shot"],
	"size": [208, 150],
	"origin": [104, 122],
	"duration": 3.8,
	"loop": false,
	"fps": 30,
	"bg": "ground",
	"options": {
		"palette": ["#12081f", "#2a0f4d", "#481b8c", "#7330d0", "#a35cff", "#cf9bff", "#f1dcff", "#ffffff"],
		"width": 28,
		"seed": 6,
	},
}

const OPEN := 0.3
const BELCH := [0.52, 0.76]
const BURST := 1.0
const SHUT := 1.9
const POP := 2.22
const SY := 0.34
static var VOID := Px.hex("#06030b")
static var FUME := Px.hex("#3a3046")
static var STONE := ["#1a1424", "#2b2639", "#4a4263", "#6c6488", "#9a91b4"].map(func(h): return Px.hex(h))
static var DUST := Px.hex("#5a5070")


# the rift's size over its life: a tear that snaps open past round, breathes, swells as it shuts, then collapses
static func radius(t: float, RX: float) -> float:
	if t < OPEN:
		return RX * Px.Ease.outBack(Px.clamp(t / OPEN), 2.2)
	if t < SHUT:
		var e := t - BURST - 0.05
		return RX * (1.0 + 0.035 * sin(t * 9.0) + 0.1 * Px.exp(-(e * e) / 0.006))
	var k := Px.clamp((t - SHUT) / (POP - SHUT))
	return RX * (1.0 + 0.1 * sin((k / 0.35) * PI * 0.5) if k < 0.35 else 1.1 * (1.0 - pow((k - 0.35) / 0.65, 1.6)))


# how far the swirl has turned: lazy, then whipping round as it shuts
static func spinAt(t: float) -> float:
	return t * 2.4 + 1.5 * Px.smooth(BURST - 0.1, BURST + 0.3, t) + 10.0 * pow(Px.clamp((t - SHUT) / (POP - SHUT)), 2.2)

static func lipAt(th: float, spin: float) -> float:
	return 1.0 + 0.05 * Px.noise(th * 3.0 + spin * 0.6, 5) + 0.035 * Px.noise(th * 8.0 - spin * 1.3, 9)


# the hole: a void, a lit far wall, three arms of light spiralling down into it
static func hole(p: Px.Painter, C: Array, rx: float, spin: float, heat: float, wind: float = 2.3) -> void:
	if rx < 1.0:
		return
	var ry := rx * SY
	var VD: int = VOID
	p.shade(-rx - 2.0, -ry - 2.0, rx + 2.0, ry + 2.0, func(x, y, out):
		var u: float = x / rx
		var v: float = y / ry
		var q := Px.hypot(u, v)
		var th := atan2(v, u)
		var lp := lipAt(th, spin)
		if q > lp:
			return
		var w := q / lp
		# the far inner wall catches the glow from below; the near one is hidden
		out.c = (C[2] if w > 0.86 else C[1]) if (v < 0.0 and w > 0.72) else (C[0] if w > 0.55 else VD))
	var n := maxf(40.0, Px.round(rx * 5.0))
	for i in 3:
		var j := 0
		while j <= n:
			var q := 0.14 + 0.82 * (j / n)
			var th := spin + (i * TAU) / 3.0 - wind * log(q)
			var lp := lipAt(th, spin)
			var x := cos(th) * q * lp * rx
			var y := sin(th) * q * lp * ry
			var c: int = (WHITE if heat > 1.1 else C[6]) if q > 0.8 else (C[5] if q > 0.55 else (C[4] if q > 0.32 else C[3]))
			p.dot(x, y, c, 1.0 if q > 0.3 else q / 0.3)
			# a fainter strand riding just inside each arm
			if q > 0.4 and j % 2 == 0:
				var t2 := th - 0.32
				var x2 := cos(t2) * q * 0.94 * lp * rx
				var y2 := sin(t2) * q * 0.94 * lp * ry
				p.dot(x2, y2, C[4] if q > 0.7 else C[3], 0.85)
			j += 1
	p.glow(0.0, 0.0, rx * 0.45, C[3], 0.35 * heat)


# the lip: a ragged ring of white-hot light, a dark cut outside it; far half behind, near half in front
static func lip(p: Px.Painter, C: Array, rx: float, spin: float, heat: float, near: bool) -> void:
	if rx < 1.0:
		return
	var ry := rx * SY
	var n := ceilf(rx * 7.0)
	var j := 0
	while j < n:
		var th := (j / n) * TAU
		var s := sin(th)
		if (s >= 0.0) != near:
			j += 1
			continue
		var l := lipAt(th, spin)
		var x := cos(th) * rx * l
		var y := s * ry * l
		var f := Px.noise(th * 9.0 + spin * 3.0, 13)
		p.dot(cos(th) * (rx * l + 1.2), s * (ry * l + 1.0), C[1])
		p.dot(x, y, (WHITE if (f > -0.3 or heat > 1.1) else C[6]) if near else (C[6] if f > 0.2 else C[5]))
		if j % 6 == 0:
			p.glow(x, y, 7.0, C[5], (0.3 if near else 0.2) * minf(1.4, heat))
		j += 1


var C: Array
var RX: float
var R: Px.Rng
var SM: Array
var ps: Px.Particles
var rocks: Px.Bits
var lights: Px.Lights
var swirl: Array = []
var wisps: Array = []
var rings: Array = []
var done := {}
var t := 0.0


func create(o: Dictionary) -> void:
	C = Px.fit(o.palette, 8)
	RX = o.width
	R = Px.Rng.new(o.seed)
	var floor_ := func(): return 0.0
	# violet smoke, dulled toward a smoky grey so it reads as smoke and not as glass
	SM = [Px.mix(C[4], FUME, 0.4), Px.mix(C[3], FUME, 0.3), Px.mix(C[5], FUME, 0.55)]
	ps = Px.Particles.new({"rng": R, "ground": floor_, "sparks": [C[7], C[6], C[5], C[3]]})
	rocks = Px.Bits.new({"ground": floor_})
	lights = Px.Lights.new()


# a mote riding the swirl on the floor plane, spiralling in
func addSwirl(r0: float) -> void:
	swirl.append({"a": R.range(0.0, TAU), "r": r0, "w": R.range(2.2, 4.0), "in": R.range(0.3, 0.7), "c": R.pick([WHITE, C[6], C[6], C[5]])})


# a streak of light sucked in from the air round the rift
func pull() -> void:
	var a := R.range(PI * 1.03, PI * 1.97)
	var D := R.range(40.0, 86.0)
	var T := R.range(0.24, 0.42)
	var x := cos(a) * D * 1.08
	var y := sin(a) * D * 0.85
	var l := Px.hypot(x, y)
	var v := (0.6 * l) / (1.0 - Px.exp(-0.6 * T))
	ps.spawn(P.MOTE, x, y, (-x / l) * v, (-y / l) * v, T, R.pick([WHITE, C[6], C[5], C[5], C[4]]), R.range(1.0, 1.7))


func puff(n: int, big: bool, sp: float) -> void:
	for i in n:
		var a := R.range(0.0, TAU)
		var d := R.range(0.0, 0.55) * RX
		ps.spawn(P.SMOKE, cos(a) * d, sin(a) * d * SY - 2.0, R.range(-1.0, 1.0) * sp * 0.6, -R.range(0.4, 1.0) * sp, R.range(1.2, 2.2) * (1.15 if big else 0.8), R.pick(SM), R.range(2.8, 4.6) * (1.15 if big else 0.9), R.range(0.0, 0.3) if big else R.range(0.0, 0.1), PF.BIG if big else 0)


func sparks(n: int, up: float, spread: float) -> void:
	for i in n:
		var a := -PI / 2.0 + R.range(-spread, spread)
		var sp := R.range(0.5, 1.0) * up
		ps.spawn(P.SPARK, R.range(-0.5, 0.5) * RX, -1.0, cos(a) * sp, sin(a) * sp, R.range(0.35, 0.8))


func once(k: String, at: float) -> bool:
	if not done.get(k, false) and t >= at:
		done[k] = true
		return true
	return false


func update(dt: float) -> void:
	t += dt
	# the tear pulls dust and light in while it opens, while it's open, and hard while it shuts
	var shutting := t > SHUT and t < POP
	if (t < OPEN + 0.15 or shutting) and R.chance(0.55):
		var s := R.sign()
		var D := R.range(RX * 1.3, RX * 2.4)
		var T := R.range(0.18, 0.3)
		var v := (D * 3.0) / (Px.exp(3.0 * T) - 1.0)
		ps.spawn(P.STREAK, s * D, -R.range(0.0, 3.0), -s * v, R.range(-2.0, 2.0), T, C[6] if R.chance(0.5) else C[5])
	if t > 0.1 and t < POP - 0.1 and R.chance(0.85 if shutting else (0.55 if t < BURST else 0.1)):
		pull()
	if t < POP and t > 0.12 and R.chance(0.5 if shutting else 0.25):
		addSwirl(R.range(1.1, 1.5))
	if once("open", OPEN * 0.7):
		lights.add(0.0, -8.0, 50.0, C[4], 0.75, 0.45)
		rings.append({"t0": t, "life": 0.42, "r0": RX * 0.8, "r1": RX * 1.9, "th": 2.5, "hot": true})
		for i in 8:
			ps.spawn(P.DUST, R.sign() * R.range(0.7, 1.1) * RX, -1.0, R.sign() * R.range(10.0, 45.0), -R.range(4.0, 14.0), R.range(0.4, 0.7), DUST, R.range(1.5, 3.0))
	# two small belches before the big one: a burp of smoke and a few sparks
	if once("b0", BELCH[0]):
		puff(6, false, 34.0)
		sparks(8, 210.0, 0.55)
		lights.add(0.0, -6.0, 44.0, C[4], 0.6, 0.3)
	if once("b1", BELCH[1]):
		puff(8, false, 40.0)
		sparks(12, 240.0, 0.6)
		lights.add(0.0, -6.0, 48.0, C[4], 0.65, 0.3)
	# the burst: something comes up through it
	if once("burst", BURST):
		lights.add(0.0, -26.0, 74.0, C[4], 1.0, 0.75)
		lights.add(0.0, -10.0, 40.0, WHITE, 0.85, 0.14)
		rings.append({"t0": t, "life": 0.55, "r0": RX * 1.0, "r1": RX * 2.5, "th": 3.5, "hot": true})
		rings.append({"t0": t + 0.06, "life": 0.45, "r0": RX * 0.8, "r1": RX * 1.8, "th": 2.0, "hot": false})
		puff(18, true, 70.0)
		sparks(34, 400.0, 0.8)
		for i in 5:
			var a := -PI / 2.0 + (i - 2) * 0.27 + R.range(-0.08, 0.08)
			var sp := R.range(185.0, 235.0)
			wisps.append({"x": R.range(-4.0, 4.0), "y": -2.0, "vx": cos(a) * sp, "vy": sin(a) * sp, "life": R.range(0.75, 1.0), "max": 1.0, "tr": [], "acc": 0.0, "ph": R.range(0.0, TAU)})
		for i in 12:
			rocks.add({"kind": B.CHUNK, "x": R.sign() * R.range(0.75, 1.05) * RX, "y": -1.0, "vx": R.range(-100.0, 100.0), "vy": -R.range(150.0, 280.0), "g": 1.0, "drag": 0.4, "bounce": 0.3, "life": R.range(1.3, 1.9), "a": R.range(0.0, TAU), "va": R.range(-14.0, 14.0), "s": R.range(1.0, 2.4), "ramp": STONE})
		for i in 14:
			ps.spawn(P.STAR, R.range(-0.8, 0.8) * RX, -R.range(4.0, 34.0), R.range(-30.0, 30.0), -R.range(10.0, 60.0), R.range(0.5, 1.1), R.pick([WHITE, C[6], C[5]]), R.range(0.8, 2.0))
	# while it's open it keeps venting thin smoke and the odd spark
	if t > OPEN and t < SHUT and R.chance(0.16):
		puff(1, false, 22.0)
	if t > OPEN and t < SHUT + 0.1 and R.chance(0.06):
		sparks(1, 160.0, 0.4)
	# the pop when it closes
	if once("pop", POP):
		lights.add(0.0, -4.0, 50.0, C[4], 0.95, 0.5)
		lights.add(0.0, -2.0, 28.0, WHITE, 0.9, 0.12)
		rings.append({"t0": t, "life": 0.35, "r0": 2.0, "r1": RX * 1.9, "th": 2.5, "hot": true})
		for i in 18:
			var a := R.range(-PI, 0.0)
			var sp := R.range(90.0, 270.0)
			ps.spawn(P.SPARK, 0.0, -1.0, cos(a) * sp, sin(a) * sp * 0.8, R.range(0.25, 0.6))
		for i in 9:
			var a := R.range(0.0, TAU)
			var sp := R.range(30.0, 95.0)
			ps.spawn(P.STAR, 0.0, -2.0, cos(a) * sp, sin(a) * sp * 0.5 - 20.0, R.range(0.4, 0.9), R.pick([WHITE, C[6]]), R.range(0.8, 1.8))
		for i in 6:
			ps.spawn(P.SMOKE, R.range(-6.0, 6.0), -R.range(1.0, 4.0), R.range(-34.0, 34.0), -R.range(10.0, 30.0), R.range(0.8, 1.3), SM[2], R.range(2.5, 4.5))
		# what's left on the floor: specks of light that twinkle out where the rift was
		for i in 14:
			ps.spawn(P.STAR, R.range(-1.0, 1.0) * RX * 0.9, -R.range(0.5, 2.0), R.range(-4.0, 4.0), -R.range(0.0, 4.0), R.range(0.6, 1.4), R.pick([C[6], C[5], C[5]]), R.range(0.4, 0.9), R.range(0.0, 0.25))
	var i := swirl.size() - 1
	while i >= 0:
		var s: Dictionary = swirl[i]
		var k := 2.4 if shutting else 1.0
		s.a += s.w * k * dt * (1.4 / maxf(0.3, s.r))
		s.r -= s["in"] * k * dt
		if s.r < 0.25 or t > POP:
			swirl.remove_at(i)
		i -= 1
	# the wisps: comets with smoky tails that arc up and out, then burst
	i = wisps.size() - 1
	while i >= 0:
		var w: Dictionary = wisps[i]
		w.tr.push_front([w.x, w.y])
		if w.tr.size() > 12:
			w.tr.pop_back()
		# a wisp bursts when it runs out or comes down on the floor
		w.life -= dt
		if w.life <= 0.0 or (w.vy > 0.0 and w.y > -2.0):
			for j in 8:
				var a := R.range(0.0, TAU)
				var sp := R.range(30.0, 120.0)
				ps.spawn(P.SPARK, w.x, w.y, cos(a) * sp + w.vx * 0.2, sin(a) * sp + w.vy * 0.2, R.range(0.2, 0.5))
			ps.spawn(P.STAR, w.x, w.y, 0.0, -6.0, 0.45, WHITE, 2.4)
			lights.add(w.x, w.y, 24.0, C[5], 0.65, 0.25)
			wisps.remove_at(i)
			i -= 1
			continue
		w.vy += 360.0 * dt
		w.vx += sin((w.max - w.life) * 16.0 + w.ph) * 160.0 * dt
		w.vx -= w.vx * 1.1 * dt
		w.vy -= w.vy * 1.1 * dt
		w.x += w.vx * dt
		w.y += w.vy * dt
		w.acc += dt
		while w.acc > 0.03:
			ps.spawn(P.SMOKE, w.x, w.y, w.vx * 0.05, w.vy * 0.05 - 4.0, R.range(0.6, 1.0), SM[0], R.range(1.5, 2.4))
			w.acc -= 0.03
		if R.chance(0.3):
			ps.spawn(P.MOTE, w.x, w.y, -w.vx * 0.2 + R.range(-15.0, 15.0), -w.vy * 0.2 + R.range(-15.0, 15.0), R.range(0.2, 0.4), C[6], 0.6)
		i -= 1
	i = rings.size() - 1
	while i >= 0:
		if t - rings[i].t0 > rings[i].life:
			rings.remove_at(i)
		i -= 1
	rocks.update(dt)
	for b in rocks.list:
		if b.rest and not b.get("dusted", false):
			b.dusted = true
			for j in 2:
				ps.spawn(P.DUST, b.x + R.range(-1.5, 1.5), -0.5, R.sign() * R.range(6.0, 30.0), -R.range(2.0, 12.0), R.range(0.3, 0.6), DUST, R.range(1.2, 2.4))
	ps.update(dt)
	lights.update(dt)


func drawBack(p: Px.Painter) -> void:
	var rx := radius(t, RX)
	var spin := spinAt(t)
	var e := t - BURST
	var heat := 0.85 + 0.15 * sin(t * 7.0) + 0.6 * Px.exp(-(e * e) / 0.01)
	# the floor glows violet round the hole
	if t < POP:
		p.glow(0.0, -4.0, rx * 1.8 + 10.0, C[4], 0.32 * Px.clamp(rx / RX))
		# and light wells up out of it into the air
		p.glowLine(0.0, -2.0, 0.0, -44.0, rx * 0.7 + 6.0, C[4], 0.16 * Px.clamp(rx / RX))
	# the slit it tears open from
	if t < OPEN * 0.6:
		var k := t / (OPEN * 0.6)
		var L := RX * 1.1 * Px.Ease.outCubic(k)
		p.line(-L, 0.0, L, 0.0, func(u): return WHITE if absf(u - 0.5) < 0.3 else C[6])
		p.glowLine(-L, 0.0, L, 0.0, 7.0, C[5], 0.6)
	if t > OPEN * 0.35 and t < POP:
		# the arms wind tighter as it twists shut
		hole(p, C, rx, spin, heat + 0.4 * Px.smooth(SHUT, POP, t), 2.3 + 2.6 * Px.smooth(SHUT, POP - 0.05, t))
		lip(p, C, rx, spin, heat, false)
	for r in rings:
		ring(p, C, r, t, false)
	drawSwirl(p, false)
	ps.draw(p, "back")


func draw(p: Px.Painter) -> void:
	var rx := radius(t, RX)
	var spin := spinAt(t)
	var e := t - BURST
	var heat := 0.85 + 0.15 * sin(t * 7.0) + 0.6 * Px.exp(-(e * e) / 0.01)
	if t > OPEN * 0.35 and t < POP:
		lip(p, C, rx, spin, heat, true)
	for r in rings:
		ring(p, C, r, t, true)
	drawSwirl(p, true)
	# the burst: a column of light shoots up out of the hole, thins and lifts away
	var b := t - BURST
	if b > 0.0 and b < 0.45:
		var k := b / 0.45
		var top := -84.0 * Px.Ease.outExpo(Px.clamp(b / 0.14))
		var bot := -1.0 - 60.0 * Px.Ease.inQuad(k)
		var w0 := RX * 0.55 * (1.0 - k * 0.8)
		var tt := t
		p.shade(-w0 - 1.0, top, w0 + 1.0, bot, func(x, y, out):
			var u: float = (y - bot) / (top - bot)
			var half: float = w0 * pow(1.0 - u, 0.8) * (0.85 + 0.15 * sin(y * 0.7 + tt * 40.0))
			var d: float = absf(x) / maxf(0.5, half)
			if d > 1.0:
				return
			out.c = WHITE if d < 0.35 else (C[6] if d < 0.7 else C[5]))
		p.glowLine(0.0, bot, 0.0, top, w0 + 12.0, C[5], 0.55 * (1.0 - k))
		if b < 0.14:
			Px.flare(p, 0.0, -4.0, 36.0 * (1.0 - b / 0.14), 1.0 - b / 0.14, C)
	# the collapse: a white point that pops
	var q := t - POP
	if q > -0.08 and q < 0.25:
		Px.sparkle(p, 0.0, -1.0, Px.round((4.0 if q < 0.0 else 12.0) * (1.0 - Px.clamp(q / 0.25))), WHITE, C[5], 0.7 * (1.0 - Px.clamp(q / 0.25)))
	rocks.draw(p)
	for w in wisps:
		var k: float = w.life / w.max
		var tr: Array = w.tr
		for i in range(1, tr.size()):
			var x0: float = tr[i - 1][0]
			var y0: float = tr[i - 1][1]
			var x1: float = tr[i][0]
			var y1: float = tr[i][1]
			var u := i / float(tr.size())
			p.line(x0, y0, x1, y1, WHITE if u < 0.25 else (C[6] if u < 0.55 else C[4]), 1.15 - u)
			if u < 0.35:
				p.line(x0 + 1.0, y0, x1 + 1.0, y1, C[5], 1.0)
		p.circle(w.x, w.y, 2.0, C[5])
		p.circle(w.x, w.y, 1.2, C[6])
		p.px(w.x, w.y, WHITE)
		p.glow(w.x, w.y, 12.0, C[5], 0.5 * k + 0.2)
	ps.draw(p, "front")
	lights.draw(p)


func drawSwirl(p: Px.Painter, near: bool) -> void:
	var rx := radius(t, RX)
	for s in swirl:
		for j in 3:
			var a: float = s.a - j * 0.08 * (1.4 / maxf(0.3, s.r))
			var x: float = cos(a) * s.r * rx
			var y: float = sin(a) * s.r * rx * SY
			if (sin(a) >= 0.0) != near:
				continue
			p.dot(x, y - 0.5, C[5] if j else s.c, 0.9 - j * 0.3 if j else 1.0)
			if not j:
				p.glow(x, y, 3.0, C[5], 0.35)


# a shock ring on the floor plane: far half behind, near half in front
static func ring(p: Px.Painter, C: Array, r: Dictionary, t: float, near: bool) -> void:
	var k: float = (t - r.t0) / r.life
	if k < 0.0 or k >= 1.0:
		return
	Px.band(p, 0.0, 0.0, r.r0 + (r.r1 - r.r0) * Px.Ease.outCubic(k), SY * 0.62, maxf(1.0, r.th * (1.0 - k)), 1.15 - k, C, func(g: float) -> bool: return (sin(g) >= 0.0) == near, r.hot and k < 0.15)
