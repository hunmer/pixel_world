# The pillar's strands of light and the rings climbing it adapt Sprite Fusion's open-source holy light
# (https://www.spritefusion.com/pixel-art-vfx/holy-light), and the streaks rushing in its power-up
# (https://www.spritefusion.com/pixel-art-vfx/power-up), MIT License, Copyright (c) 2026 Hugo Duprez.
# port-of: src/fx/ui/level-up.js@073eb7535ddfa4500150474847085e0c4a7ee62d
extends "../../core/effect.gd"

const Px := preload("../../core/px.gd")
const Lib := preload("_lib.gd")
const P := Px.P
const PF := Px.PF
const WHITE := Px.WHITE

static var meta := {
	"name": "Level up",
	"desc": "Gold gathers at the feet and bursts up as a pillar of light round the hero; rings climb it, LEVEL UP! drops in letter by letter, a shine sweeps it, sparkles twinkle.",
	"tags": ["ui", "level", "reward", "text", "light", "one-shot"],
	"size": [176, 138],
	"origin": [88, 114],
	"duration": 3.2,
	"loop": false,
	"fps": 30,
	"bg": "ground",
	"actor": 2,
	"options": {"palette": ["#2a1405", "#5c3008", "#9a5a0e", "#d48e18", "#f5b92c", "#ffde5e", "#fff4bc", "#ffffff"], "text": "LEVEL UP!", "seed": 5},
}

static var COIL := {"turn": 0.9, "crouch": 7, "lean": 2, "fx": -6, "fy": -13, "bx": 7, "by": -13, "ffx": -5, "fbx": 6}
static var LEAP := {"turn": 1.1, "y": -16, "crouch": -1, "fx": -6, "fy": -45, "bx": 7, "by": -44, "ffx": -2, "ffy": -8, "fbx": 5, "fby": -3, "toeB": true}
static var PUMP := {"turn": 0.9, "crouch": 0, "fx": -6, "fy": -45, "bx": 9, "by": -15, "ffx": -3, "fbx": 4}
static var act := {
	"onBody": true,
	"follow": 0,
	"poses": [
		[-0.3, Px.READY],
		[0.28, COIL],
		[0.3, LEAP, "snap"],
		[0.46, Px.merge(LEAP, {"y": -19})],
		[0.72, Px.merge(LEAP, {"y": 0, "ffy": -4, "fby": -4}), "in"],
		[0.74, Px.merge(COIL, {"crouch": 5}), "snap"],
		[0.95, PUMP, "out"],
		[1.2, Px.merge(PUMP, {"crouch": 1, "fy": -43})],
		[1.45, PUMP],
		[2.3, Px.merge(PUMP, {"fy": -41})],
		[2.8, Px.READY],
		[3.2, Px.READY],
	],
	"hits": [{"t": 0.28, "stop": 0.05, "shake": 0.14, "amp": 2}],
	"dust": [{"t": 0.3, "x": 0, "n": 7}, {"t": 0.74, "x": 0, "n": 6}],
}

# release, pillar lifts off, pillar gone, pillar height, text top, first letter, stagger, shine, letters pop
const REL := 0.28
const RET := 1.02
const GONE := 1.34
const TOP := 100.0
const TY := -68.0
const DROP := 0.5
const STAG := 0.05
const LANDED := 1.06
const SHINE := 1.24
const EXIT := 2.3


static func _strands() -> Array:
	return Px.arr(9, func(i: int): return {"x": (i / 8.0 - 0.5) * 1.5 + (Px.rand(i, 1) - 0.5) * 0.16, "sp": 170.0 + Px.rand(i, 2) * 170.0, "per": 10.0 + Px.rand(i, 3) * 16.0, "duty": 0.3 + Px.rand(i, 4) * 0.35, "ph": Px.rand(i, 5), "lvl": 1 if Px.rand(i, 6) < 0.35 else 2, "end": 0.5 + Px.rand(i, 7) * 0.42})


# strands of light streaming up the pillar in dashes: where across it, how fast, dash period and length
static var STRANDS := _strands()


# half-width of the pillar at time t
static func widthAt(t: float) -> float:
	return 0.0 if t < REL else 12.0 * (1.0 + 0.4 * exp(-(t - REL) * 10.0)) * (1.0 - 0.82 * Px.smooth(RET - 0.12, RET + 0.16, t))


# the pillar: shoots up from the feet (one white-hot frame), then stands as light, not paint: two flowing
# walls, a white core and strands streaming up in dashes; at the end its foot lifts off and it shoots away
static func column(p: Px.Painter, C: Array, t: float) -> void:
	var a := t - REL
	if a < 0.0 or t > GONE:
		return
	var top := -TOP * Px.Ease.outExpo(Px.clamp(a / 0.12))
	var bot := -TOP * Px.Ease.inCubic(Px.seg(t, RET, GONE))
	var W := widthAt(t)
	var k := 1.0 - Px.smooth(RET, GONE, t)
	p.glowLine(0.0, top, 0.0, minf(bot, -34.0), W * 1.6 + 6.0, C[5], 0.2 * k + 0.06)
	p.glowLine(0.0, top, 0.0, minf(bot, -40.0), 5.0, WHITE, 0.18 * k)
	if a < 0.04:
		var y := floorf(top)
		while y < bot:
			var wr := W * 0.55 * (1.0 - 0.3 * (-y / TOP))
			var x := floorf(-wr)
			while x <= ceilf(wr):
				p.dot(x, y, WHITE if absf(x + 0.5) < wr - 1.5 else C[6], Px.clamp((y + TOP) / 20.0) * 1.5)
				x += 1.0
			y += 1.0
		return
	var y := ceilf(top)
	while y < ceilf(bot):
		var h := -y / TOP
		var fade := Px.clamp((y + TOP) / 16.0) * (1.0 if t < RET else Px.clamp((bot - y) / 10.0))
		var head := y - top < 3.0 and a < 0.16
		var wr := W * (1.0 - 0.3 * h) + 0.9 * Px.noise2(y * 0.2, t * 12.0, 3)
		for s in [-1.0, 1.0]:
			var run := Px.fract(y * 0.06 + t * 3.4 + (0.5 if s > 0.0 else 0.0)) < 0.78
			var xw: float = s * wr
			p.dot(xw, y, WHITE if head else (C[6] if run else C[5]), fade * 1.4)
			p.dot(xw + s, y, C[4], fade * (0.5 if run else 0.25))
			if run:
				p.dot(xw - s, y, C[5], fade * 1.2)
		p.dot(0.0, y, WHITE, fade * 1.6)
		p.dot(-1.0, y, WHITE if Px.noise2(y * 0.3, t * 14.0, 5) > -0.2 else C[6], fade * 1.3)
		if Px.noise2(y * 0.25, t * 9.0, 8) > 0.25:
			p.dot(1.0, y, C[6], fade * 1.2)
		for S: Dictionary in STRANDS:
			if h > S.end:
				continue
			var ph := Px.fract((y + t * S.sp) / S.per + S.ph)
			if ph > S.duty:
				continue
			var u: float = ph / S.duty
			p.px(S.x * wr, y, WHITE if (head or u < 0.2) else (C[7 - S.lvl] if u < 0.65 else C[6 - S.lvl]))
		y += 1.0


# the plate of light the pillar stands on
static func plate(p: Px.Painter, C: Array, t: float, k: float) -> void:
	if k <= 0.02:
		return
	var rx := 9.0 + 9.0 * k + sin(t * 9.0)
	var ry := 2.2
	p.shade(-rx, -ry, rx, ry, func(x: float, y: float, o):
		var dx := x / rx
		var dy := y / ry
		var d := sqrt(dx * dx + dy * dy)
		if d > 1.0:
			return null
		var u := d / maxf(0.05, k)
		o.c = WHITE if u < 0.3 else (C[6] if u < 0.55 else (C[5] if u < 0.8 else C[4]))
		o.a = 1.0 if d < 0.6 * k else k * (1.0 - d) * 2.2
		return null)
	p.glow(0.0, -1.0, rx * 2.2, C[4], 0.35 * k)


# a burst of rays above and below the title: they start on an ellipse just outside the word, so none crosses
# it, shoot out when the last letter lands, shimmer, and draw back in
static func rays(p: Px.Painter, C: Array, t: float, k: float, cx: float, cy: float) -> void:
	if k <= 0.02:
		return
	for i in 20:
		var an := (i / 20.0) * TAU + 0.08
		var ca := cos(an)
		var sa := sin(an)
		var long := i % 2 == 0
		if absf(sa) < 0.4:
			continue
		var r0 := 1.0 / sqrt(pow(ca / 52.0, 2.0) + pow(sa / 12.0, 2.0)) + 2.0 * k
		var len_ := (15.0 + 7.0 * Px.rand(i, 9) if long else 7.0 + 4.0 * Px.rand(i, 8)) * k
		if len_ < 1.0:
			continue
		var sh := 0.75 + 0.25 * sin(t * 7.0 + i * 2.1)
		var x0 := cx + ca * r0
		var y0 := cy + sa * r0
		p.line(x0, y0, x0 + ca * len_, y0 + sa * len_, func(u: float): return C[7] if u < 0.3 else (C[6] if u < 0.6 else C[5]), func(u: float): return sh * (1.3 if u < 0.55 else (1.3 * (1.0 - u)) / 0.45))


var C: Array
var R: Px.Rng
var A: Variant
var SHADOW: int
var ps: Px.Particles
var lights: Px.Lights
var word: Dictionary
var BASE := TY + 14.0
var X0: float
var lets: Array
var right: float
var sats: Array
var halos := []
var t := 0.0
var released := false
var nextHalo := REL + 0.03
var gather := 0.0
var rush := []


func create(o: Dictionary) -> void:
	C = Px.fit(o.palette, 8)
	R = Px.Rng.new(o.seed)
	A = o.get("actor")
	SHADOW = Px.scale(C[0], 0.5)
	ps = Px.Particles.new({"rng": R, "ground": func(): return 0.0, "sparks": [C[7], C[6], C[5], C[3]]})
	lights = Px.Lights.new()
	word = Lib.spell(o.text)
	X0 = -word.w
	lets = []
	var i := 0
	for L: Dictionary in word.letters:
		if L.g == null:
			continue
		lets.append({"g": L.g, "w": L.w, "cx": X0 + (L.x + L.w / 2.0) * 2.0, "born": DROP + i * STAG, "pop": EXIT + i * 0.04, "off": -18.0, "v": 60.0, "sq": 0.0, "flash": 0.0, "on": false, "landed": false, "rest": false, "burst": false})
		i += 1
	right = X0 + word.w * 2.0
	# sparkles that pop round the title one after another
	sats = Px.arr(8, func(j: int):
		var s := 1.0 if j % 2 else -1.0
		var x := s * R.range(20.0, 60.0)
		var y := TY + 7.0 + (R.sign() * R.range(11.0, 18.0) if absf(x) < 50.0 else R.range(-14.0, 14.0))
		return {"x": x, "y": y, "t0": SHINE - 0.1 + j * 0.13 + R.range(0.0, 0.05), "dur": R.range(0.32, 0.5), "L": R.range(3.0, 6.0)})


# every particle is gone by the end
func spawn(k: int, x: float, y: float, vx: float, vy: float, life: float, col: Variant = WHITE, size: float = 1.0, delay: float = 0.0, flag: int = 0) -> void:
	ps.spawn(k, x, y, vx, vy, minf(life, meta.duration - 0.05 - t), col, size, delay, flag)


# a gathering streak: a gold tail and a white head, running straight in
func drawRush(p: Px.Painter, back: bool) -> void:
	for m: Dictionary in rush:
		if m.back != back:
			continue
		var sp := Px.hypot(m.vx, m.vy)
		var ux: float = m.vx / sp
		var uy: float = m.vy / sp
		var L: float = m.len
		p.line(m.x - ux * L, m.y - uy * L, m.x - ux * L * 0.4, m.y - uy * L * 0.4, m.c)
		p.line(m.x - ux * L * 0.35, m.y - uy * L * 0.35, m.x, m.y, WHITE)
		p.glow(m.x, m.y, 4.0, C[5], 0.25)


func update(dt: float) -> void:
	t += dt
	# the gathering: streaks pour in along the floor to the feet and in from all round to the body, and in the
	# last beat run up the hero from the feet; the late ones are swallowed by the burst
	gather += dt * 420.0 if t < REL else 0.0
	while gather >= 1.0:
		var kind := R.next()
		var sp := R.range(140.0, 250.0) * (1.0 + t * 2.0)
		var x: float
		var y: float
		var tx: float
		var ty: float
		if kind < 0.42:
			var an := R.range(0.0, TAU)
			var D := R.range(22.0, 70.0)
			x = cos(an) * D
			y = -1.0 - absf(sin(an)) * D * 0.1
			tx = cos(an) * 3.0
			ty = -1.0
		elif kind < 0.84:
			var an := R.range(0.0, TAU)
			var D := R.range(34.0, 64.0)
			x = cos(an) * D
			y = minf(-3.0, -20.0 + sin(an) * D * 0.85)
			tx = cos(an) * 11.0
			ty = -20.0 + sin(an) * 14.0
		else:
			if t < REL * 0.4:
				gather -= 1.0
				continue
			x = R.range(-9.0, 9.0)
			y = -1.0
			tx = x * 0.7
			ty = -R.range(26.0, 44.0)
		var dx := tx - x
		var dy := ty - y
		var l := Px.hypot(dx, dy)
		if not l:
			l = 1.0
		rush.append({"x": x, "y": y, "vx": (dx / l) * sp, "vy": (dy / l) * sp, "life": minf(l / sp, REL + 0.06 - t), "len": R.range(5.0, 9.0), "c": C[6] if R.chance(0.45) else C[5], "back": kind > 0.84 and R.chance(0.5)})
		gather -= 1.0
	var i := rush.size() - 1
	while i >= 0:
		var m: Dictionary = rush[i]
		m.life -= dt
		if m.life <= 0.0:
			rush.remove_at(i)
		else:
			m.x += m.vx * dt
			m.y += m.vy * dt
		i -= 1
	if t < REL and R.chance(0.12):
		spawn(P.STAR, R.range(-30.0, 30.0), -R.range(0.0, 3.0), 0.0, -R.range(10.0, 30.0), R.range(0.3, 0.5), C[6], 0.6)
	if not released and t >= REL:
		released = true
		lights.add(0.0, -24.0, 90.0, C[5], 0.6, 0.7)
		lights.add(0.0, -8.0, 40.0, WHITE, 0.6, 0.12)
		# speed lines flung out from the hero
		for j in 22:
			var an := (j / 22.0) * TAU + R.range(-0.12, 0.12)
			var sp := R.range(260.0, 460.0)
			var y0 := -18.0 + sin(an) * 8.0
			var vy := sin(an) * sp * 0.8
			var life := minf(minf(R.range(0.1, 0.2), (-y0 / vy) if vy > 0.0 else ((y0 + 104.0) / -vy if vy < 0.0 else 1.0)), 78.0 / absf(cos(an) * sp))
			spawn(P.MOTE, cos(an) * 6.0, y0, cos(an) * sp, vy, life, C[7] if R.chance(0.4) else C[6], 1.0, 0.0, PF.BACK if (an > 0.3 and an < PI - 0.3) else 0)
		for j in 26:
			var an := -PI / 2.0 + R.range(-1.3, 1.3)
			var sp := R.range(120.0, 290.0)
			spawn(P.SPARK, R.range(-5.0, 5.0), -2.0, cos(an) * sp, sin(an) * sp, R.range(0.35, 0.8))
		for j in 16:
			spawn(P.STAR, R.range(-10.0, 10.0), R.range(-36.0, -4.0), R.range(-30.0, 30.0), -R.range(15.0, 60.0), R.range(0.6, 1.3), R.pick([C[7], C[6], C[5]]), R.range(1.5, 2.6) if R.chance(0.35) else R.range(0.4, 0.9), 0.0, PF.BACK if R.chance(0.4) else 0)
	var W := widthAt(t)
	if t >= nextHalo and t < RET - 0.1:
		halos.append(t)
		nextHalo += 0.16
	# streaks race up beside the pillar
	if t > REL and t < RET + 0.1 and R.chance(0.5):
		var s := R.sign()
		var y := R.range(-4.0, -60.0)
		var vy := -R.range(140.0, 260.0)
		spawn(P.MOTE, s * R.range(0.75, 1.6) * W, y, 0.0, vy, minf(R.range(0.16, 0.32), (y + 96.0) / -vy), C[7] if R.chance(0.5) else C[6], R.range(0.6, 1.0), 0.0, PF.BACK if R.chance(0.5) else 0)
	# motes rise from the floor while the light lasts
	if t > REL and t < 2.4 and R.chance(0.14 * (1.0 - Px.seg(t, 1.6, 2.4))):
		spawn(P.EMBER, R.range(-20.0, 20.0), -R.range(1.0, 30.0), R.range(-15.0, 15.0), -R.range(20.0, 55.0), R.range(0.8, 1.6), C[5], R.range(1.0, 2.0), 0.0, PF.BACK if R.chance(0.4) else 0)
	# gold motes lift off the hero while the light lasts
	if A != null and t > REL + 0.1 and t < 2.2 and R.chance(0.09):
		var m: Dictionary = A.mask
		var mw: int = m.w
		var mh: int = m.h
		for n in 12:
			var mi := R.int_(0, mw - 1)
			var mj := R.int_(0, mh - 1)
			if not m.data[mj * mw + mi]:
				continue
			spawn(P.STAR, A.x + mi + 0.5, A.y + mj + 0.5, R.range(-8.0, 8.0), -R.range(14.0, 34.0), R.range(0.6, 1.1), R.pick([C[7], C[6], C[5]]), 1.5 if R.chance(0.2) else 0.6, 0.0, PF.BACK if R.chance(0.5) else 0)
			break
	# twinkles round the title and the hero while it holds
	if t > 1.0 and t < 2.5 and R.chance(0.13):
		var up := R.chance(0.6)
		var x := R.range(-58.0, 58.0) if up else R.range(-20.0, 20.0)
		var y := TY + 7.0 + R.range(-16.0, 16.0) if up else R.range(-44.0, -6.0)
		spawn(P.STAR, x, y, R.range(-6.0, 6.0), -R.range(4.0, 14.0), R.range(0.4, 0.8), R.pick([C[7], C[6], C[6], C[5]]), R.range(1.5, 2.4) if R.chance(0.3) else 0.6, 0.0, PF.BACK if R.chance(0.3) else 0)
	# the letters drop in, bounce and settle; then pop away one by one
	for L: Dictionary in lets:
		if t < L.born:
			continue
		L.on = true
		if not L.rest:
			L.v += 1700.0 * dt
			L.off += L.v * dt
			if L.off >= 0.0 and L.v > 0.0:
				L.off = 0.0
				if L.v > 110.0:
					L.sq = 1.0
					if not L.landed:
						L.landed = true
						L.flash = 1.0
						lights.add(L.cx, BASE - 7.0, 18.0, C[5], 0.55, 0.25)
						for s in [-1.0, 1.0]:
							spawn(P.STAR, L.cx + s * L.w, BASE - R.range(0.0, 3.0), s * R.range(15.0, 40.0), -R.range(5.0, 25.0), R.range(0.25, 0.45), C[6], R.range(0.5, 1.2))
					L.v = -L.v * 0.3
				else:
					L.v = 0.0
					L.rest = true
		L.sq = maxf(0.0, L.sq - dt / 0.1)
		L.flash = maxf(0.0, L.flash - dt / 0.12)
		if not L.burst and t >= L.pop + 0.06:
			L.burst = true
			for j in 3:
				var an := R.range(0.0, TAU)
				var sp := R.range(20.0, 55.0)
				spawn(P.STAR, L.cx + R.range(-3.0, 3.0), BASE - 7.0 + R.range(-4.0, 4.0), cos(an) * sp, sin(an) * sp - 15.0, R.range(0.3, 0.6), R.pick([C[7], C[6]]), 0.6 if j else R.range(1.2, 2.0))
	ps.update(dt)
	lights.update(dt)


func drawBack(p: Px.Painter) -> void:
	rays(p, C, t, Px.Ease.outExpo(Px.seg(t, LANDED, LANDED + 0.2)) * (1.0 - Px.Ease.inQuad(Px.seg(t, EXIT - 0.15, EXIT + 0.1))), 0.0, TY + 7.0)
	if t < REL:
		var k := Px.seg(t, 0.02, REL)
		Px.band(p, 0.0, 0.0, 4.0 + 52.0 * (1.0 - Px.Ease.inQuad(k)), 0.2, 1.5, k * 1.1, C, func(g: float): return sin(g) < 0.0)
	for drt in [[0.0, 72.0, 4.0], [0.08, 46.0, 2.5]]:
		var k: float = (t - REL - drt[0]) / 0.55
		if k > 0.0 and k < 1.0:
			Px.band(p, 0.0, 0.0, 5.0 + drt[1] * Px.Ease.outCubic(k), 0.2, maxf(1.0, drt[2] * (1.0 - k)), 1.15 - k, C, func(g: float): return sin(g) < 0.0, k < 0.15)
	for h0: float in halos:
		var k := (t - h0) / 0.6
		if k > 0.0 and k < 1.0:
			Px.band(p, 0.0, -2.0 - 72.0 * Px.Ease.outQuad(k), (widthAt(t) * 1.45 + 4.0) * (1.0 - 0.4 * k), 0.3, 1.5, (1.0 - k) * 1.4, C, func(g: float): return sin(g) < 0.0, k < 0.12)
	column(p, C, t)
	plate(p, C, t, 0.55 * Px.seg(t, 0.05, REL) if t < REL else 1.0 - Px.smooth(RET - 0.1, GONE + 0.2, t))
	ps.draw(p, "back")
	drawRush(p, true)


func draw(p: Px.Painter) -> void:
	# near halves of the rings, in front of the hero
	if t < REL:
		var k := Px.seg(t, 0.02, REL)
		Px.band(p, 0.0, 0.0, 4.0 + 52.0 * (1.0 - Px.Ease.inQuad(k)), 0.2, 1.5, k * 1.1, C, func(g: float): return sin(g) >= 0.0)
	for drt in [[0.0, 72.0, 4.0], [0.08, 46.0, 2.5]]:
		var k: float = (t - REL - drt[0]) / 0.55
		if k > 0.0 and k < 1.0:
			Px.band(p, 0.0, 0.0, 5.0 + drt[1] * Px.Ease.outCubic(k), 0.2, maxf(1.0, drt[2] * (1.0 - k)), 1.15 - k, C, func(g: float): return sin(g) >= 0.0, k < 0.15)
	for h0: float in halos:
		var k := (t - h0) / 0.6
		if k > 0.0 and k < 1.0:
			Px.band(p, 0.0, -2.0 - 72.0 * Px.Ease.outQuad(k), (widthAt(t) * 1.45 + 4.0) * (1.0 - 0.4 * k), 0.3, 1.5, (1.0 - k) * 1.4, C, func(g: float): return sin(g) >= 0.0, k < 0.12)
	# the hero: warming as it gathers, flashed white on the release, then lit gold with a glowing edge
	var lit := Px.smooth(REL - 0.02, REL + 0.04, t) * (1.0 - Px.smooth(RET, 2.5, t))
	Lib.tintActor(p, A, 0.0 if t < REL else (1.0 if t < REL + 0.06 else exp(-(t - REL - 0.06) / 0.07)), [C[4], C[5], C[6]])
	Lib.lightActor(p, A, C[5], 0.1 * Px.seg(t, 0.05, REL) * (1.0 - lit) + 0.06 * lit, 0.6 * lit, t)
	Lib.haloActor(p, A, C[5], 0.85 * lit * (1.0 - Px.smooth(RET, GONE + 0.3, t)) + 0.3 * lit, t)
	# the spark gathering at the feet, then the flare of the release
	if t < REL:
		var k := Px.seg(t, 0.05, REL)
		var beat := 1.0 + 0.4 * exp(-(pow(t - REL * 0.6, 2.0)) / 0.001)
		Px.sparkle(p, 0.0, -2.0, (1.0 + 4.0 * k * k) * beat, C[6], C[5], 0.3 + 0.4 * k)
	elif t < REL + 0.22:
		var a := (t - REL) / 0.22
		Px.flare(p, 0.0, -4.0, 28.0 * pow(1.0 - a, 1.5), 1.0 - a, C)
		p.glow(0.0, -16.0, 48.0, WHITE, 0.3 * (1.0 - a))
	ps.draw(p, "front")
	drawRush(p, false)
	# the title
	var items := []
	var done := (t - LANDED) / 0.12
	for L: Dictionary in lets:
		if not L.on:
			continue
		var sx := 2.0
		var sy := 2.0
		var flash: float = L.flash
		if not L.landed and L.v > 150.0:
			sx = 1.8
			sy = 2.3
		if L.sq > 0.0:
			sx = 2.0 * (1.0 + 0.22 * L.sq)
			sy = 2.0 * (1.0 - 0.22 * L.sq)
		var pu: float = (t - L.pop) / 0.07
		var hop := Px.seg(t, L.pop - 0.1, L.pop)
		if pu >= 1.0:
			continue
		if hop > 0.0 and pu <= 0.0:
			sx = 2.0 * (1.0 - 0.1 * hop)
			sy = 2.0 * (1.0 + 0.15 * hop)
		if pu > 0.0:
			sx = 2.0 * (1.0 + 0.3 * pu)
			sy = sx
			flash = 1.0
		flash = maxf(flash, 1.0 - done if (done > 0.0 and done < 1.0) else 0.0)
		var h := 7.0 * sy
		var w: float = L.w * sx
		items.append({"g": L.g, "x": L.cx - w / 2.0, "y": BASE + L.off - h - 3.0 * Px.Ease.outQuad(hop), "sx": sx, "sy": sy, "a": Px.clamp((t - L.born) / 0.05), "flash": flash})
	var sh := Px.seg(t, SHINE, SHINE + 0.34)
	var shine: Variant = X0 - 14.0 + (right - X0 + 30.0) * Px.Ease.inOutSine(sh) if (sh > 0.0 and sh < 1.0) else null
	Lib.drawWord(p, items, {"fill": [C[3], C[4], C[5], C[6]], "edge": WHITE, "under": C[2], "outline": C[0], "shadow": SHADOW, "shine": shine, "shineY": TY, "glint": C[6]})
	if shine != null and shine > X0 and shine < right:
		p.glowLine(shine, TY, shine + 8.4, BASE, 9.0, C[6], 0.3)
	var hold := Px.smooth(0.9, 1.2, t) * (1.0 - Px.smooth(EXIT, EXIT + 0.4, t))
	if hold > 0.0:
		p.glow(0.0, TY + 7.0, 50.0, C[5], 0.22 * hold + (0.3 * (1.0 - done) if (done > 0.0 and done < 1.0) else 0.0))
	# each letter twinkles out where it popped
	for L: Dictionary in lets:
		var u: float = (t - L.pop - 0.07) / 0.16
		if u > 0.0 and u < 1.0:
			Px.sparkle(p, L.cx, BASE - 7.0, 6.0 * (1.0 - u) * (1.0 - u), C[6], C[5], 0.5)
	# the glint where the shine leaves the word, and sparkles popping round it
	var g := (t - SHINE - 0.3) / 0.26
	if g > 0.0 and g < 1.0:
		Px.sparkle(p, right - 2.0, TY + 1.0, 7.0 * sin(g * PI), C[6], C[5], 0.6)
	for s: Dictionary in sats:
		var u: float = (t - s.t0) / s.dur
		if u > 0.0 and u < 1.0:
			Px.sparkle(p, s.x, s.y, s.L * pow(sin(u * PI), 0.7), C[6], C[5], 0.5)
	lights.draw(p)
