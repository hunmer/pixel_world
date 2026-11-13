# The healing light (a soft column of glow, a lit ring on the floor, motes and bevelled crosses drifting up and
# glinting) is adapted from Sprite Fusion's open-source heal (https://www.spritefusion.com/pixel-art-vfx/heal),
# MIT License, Copyright (c) 2026 Hugo Duprez.
# port-of: src/fx/nature/healing-bloom.js@10f753d3d97181996cba65342cfb53c65be58d21
extends "../../core/effect.gd"

const Px := preload("../../core/px.gd")
const Lib := preload("_lib.gd")
const P := Px.P
const WHITE := Px.WHITE

static var meta := {
	"name": "Healing bloom",
	"desc": "A sprout pushes up and unfurls, a bud swells and opens round a glowing golden heart in a flare of healing light; its petals lift away one by one as motes.",
	"tags": ["nature", "heal", "flower", "plant", "buff", "ground", "one-shot"],
	"size": [124, 120],
	"origin": [62, 108],
	"duration": 3.3,
	"loop": false,
	"fps": 30,
	"bg": "ground",
	"options": {
		"palette": ["#0c1a10", "#173a1a", "#24582a", "#357a34", "#52a03e", "#86c84e", "#c4ec7a", "#f4ffd0"],
		"petal": ["#4a1a3a", "#a8406e", "#ec8ab0", "#ffd8e8"],
		"heart": ["#a8641a", "#f0b42e", "#ffe680", "#fffbe0"],
		"seed": 4,
	},
}

const STEM := 0.42
const BUD := 0.75
const OPEN := 1.05
const LIFT := 1.7
const WILT := 2.4
const H := 36.0
const NPET := 6


static func _ins(dx: int, dy: int, L: int) -> bool:
	return (dx == 0 and absi(dy) <= L) or (dy == 0 and absi(dx) <= L)


# a bevelled cross of light
static func cross(p: Px.Painter, x: float, y: float, L: int, C: Array, a: float, glint: bool) -> void:
	var X := Px.round(x)
	var Y := Px.round(y)
	for dy in range(-L - 1, L + 2):
		for dx in range(-L - 1, L + 2):
			if _ins(dx, dy, L):
				p.dot(X + dx, Y + dy, WHITE if (glint and not dx and not dy) else (C[6] if (dy < 0 or dx < 0) else C[5]), a)
			elif L > 1 and (_ins(dx - 1, dy, L) or _ins(dx + 1, dy, L) or _ins(dx, dy - 1, L) or _ins(dx, dy + 1, L)):
				p.dot(X + dx, Y + dy, C[2], a * 0.8)
	p.glow(x, y, 5.0 + L * 2, C[6], 0.35 * a)


var C: Array
var Pt: Array
var Ht: Array
var R: Px.Rng
var ps: Px.Particles
var lights: Px.Lights
var flying: Array
var glyphs: Array
var petals: Array
var t := 0.0
var popped := false
var sprouted := false


func create(o: Dictionary) -> void:
	C = Px.fit(o.palette, 8)
	Pt = Px.fit(o.petal, 4)
	Ht = Px.fit(o.heart, 4)
	R = Px.Rng.new(o.seed)
	var floor_ := func(): return 0.0
	ps = Px.Particles.new({"rng": R, "ground": floor_, "sparks": [Ht[3], Ht[2], Ht[1], Ht[0]]})
	lights = Px.Lights.new()
	flying = []
	glyphs = []
	petals = Px.arr(NPET, func(i: int) -> Dictionary: return {"az": (i / float(NPET)) * TAU + 0.3, "off": fmod(i * 0.7, 1.0), "gone": false, "at": LIFT + fmod(i * 0.37, 1.0) * 0.55})
	t = 0.0
	popped = false
	sprouted = false


func grow() -> float:
	return Px.Ease.outCubic(Px.clamp(t / STEM)) * (1.0 - Px.Ease.inCubic(Px.clamp((t - WILT) / 0.6)))


func sway() -> float:
	return sin(t * 2.6) * 1.4 * Px.smooth(0.2, 0.6, t)


# the stem's points, base to tip: a gentle S that sways
func stem() -> Array:
	var g := grow()
	var pts := []
	for i in 13:
		var s := i / 12.0
		pts.append([sin(s * 3.2) * 2.2 * s + sway() * s * s, (1.0 - g) * H * 1.1 - s * H])
	return pts


func open() -> float:
	return Px.Ease.outBack(Px.clamp((t - BUD) / (OPEN - BUD)), 1.4)


func update(dt: float) -> void:
	t += dt
	var f := minf(1.0, dt * 120.0)
	var top: Array = stem()[12]
	if not sprouted:
		sprouted = true
		for i in 8:
			ps.spawn(P.GRIT, R.range(-3.0, 3.0), -1.0, R.range(-40.0, 40.0), -R.range(40.0, 100.0), R.range(0.5, 0.8), R.pick([C[2], C[3]]), 1.0)
		for i in 3:
			ps.spawn(P.DUST, R.range(-3.0, 3.0), -1.0, R.sign() * R.range(10.0, 30.0), -R.range(4.0, 10.0), R.range(0.4, 0.6), C[3], R.range(1.5, 2.5))
	# the bud draws light in as it swells
	if t > STEM and t < BUD and R.chance(0.3 * f):
		var a := R.range(0.0, TAU)
		var d := R.range(14.0, 26.0)
		var x: float = top[0] + cos(a) * d
		var y: float = top[1] - 3.0 + sin(a) * d * 0.8
		ps.spawn(P.STREAK, x, y, (top[0] - x) * 3.4, (top[1] - 3.0 - y) * 3.4, R.range(0.18, 0.26), Ht[2] if R.chance(0.5) else C[6])
	if not popped and t >= OPEN - 0.12:
		popped = true
		lights.add(top[0], top[1] - 3.0, 22.0, WHITE, 0.45, 0.08)
		lights.add(top[0], top[1] - 3.0, 70.0, Ht[2], 0.5, 0.8)
		for i in 16:
			var a := R.range(0.0, TAU)
			var sp := R.range(40.0, 120.0)
			ps.spawn(P.MOTE, top[0], top[1] - 3.0, cos(a) * sp, sin(a) * sp - 20.0, R.range(0.4, 0.8), Ht[3] if R.chance(0.5) else C[7], 0.7)
		for i in 5:
			ps.spawn(P.STAR, top[0] + R.range(-10.0, 10.0), top[1] - R.range(0.0, 14.0), 0.0, -6.0, R.range(0.3, 0.6), Ht[3], R.range(1.0, 2.4), R.range(0.0, 0.3))
	# while it blooms: crosses and motes of light drift up round it
	if t > OPEN and t < WILT and R.chance(0.13 * f):
		glyphs.append({"x": R.range(-22.0, 22.0), "y": -R.range(2.0, 36.0), "t0": t, "life": minf(R.range(0.7, 1.1), meta.duration - 0.05 - t), "L": 3 if R.chance(0.35) else 2, "seed": R.next() * 9.0})
	if t > OPEN - 0.1 and t < WILT and R.chance(0.35 * f):
		ps.spawn(P.EMBER, R.range(-20.0, 20.0), -R.range(0.0, 8.0), R.range(-6.0, 6.0), -R.range(25.0, 55.0), minf(R.range(0.6, 1.1), meta.duration - 0.05 - t), C[6] if R.chance(0.6) else Ht[2], 2.0 if R.chance(0.3) else 1.0)
	var i := glyphs.size() - 1
	while i >= 0:
		if t - glyphs[i].t0 > glyphs[i].life:
			glyphs.remove_at(i)
		i -= 1
	# petals let go one by one and lift away, turning, until they twinkle out
	for q: Dictionary in petals:
		if not q.gone and t >= q.at:
			q.gone = true
			var e := PI / 2.0 - 0.15
			var dx: float = sin(e) * cos(q.az)
			var L := 10.0
			flying.append({"x": top[0] + dx * L * 0.6, "y": top[1] - 3.0 - cos(e) * L * 0.6, "vx": dx * 30.0 + R.range(-10.0, 10.0), "vy": -R.range(25.0, 45.0), "a": atan2(-cos(e), dx), "va": R.range(-5.0, 5.0), "fl": 0.0, "vf": R.range(5.0, 9.0), "life": minf(R.range(0.75, 1.0), meta.duration - 0.45 - t), "max": 0.0})
			flying[flying.size() - 1].max = flying[flying.size() - 1].life
	i = flying.size() - 1
	while i >= 0:
		var q: Dictionary = flying[i]
		q.life -= dt
		if q.life <= 0.0:
			ps.spawn(P.STAR, q.x, q.y, 0.0, -8.0, minf(0.35, meta.duration - 0.05 - t), Pt[3], 1.8)
			flying.remove_at(i)
			i -= 1
			continue
		q.vx -= q.vx * 1.5 * dt
		q.vy -= q.vy * 0.8 * dt + 10.0 * dt
		q.x += q.vx * dt + sin(q.fl) * 12.0 * dt
		q.y += q.vy * dt
		q.a += q.va * dt
		q.fl += q.vf * dt
		i -= 1
	ps.update(dt)
	lights.update(dt)


func drawBack(p: Px.Painter) -> void:
	var bloom := Px.smooth(OPEN - 0.15, OPEN + 0.2, t) * (1.0 - Px.smooth(WILT - 0.2, WILT + 0.5, t))
	var top: Array = stem()[12]
	# a column of soft healing light, and a lit ring on the floor that blooms out as it opens
	var h := 0
	while h < 70:
		p.glow(0.0, -h, 22.0, C[5], 0.12 * bloom * (1.0 - h / 80.0))
		h += 7
	var k := Px.clamp((t - OPEN + 0.12) / 0.6)
	if k > 0.0 and k < 1.0:
		Px.band(p, 0.0, 0.5, 6.0 + 30.0 * Px.Ease.outCubic(k), 0.18, maxf(1.0, 3.0 * (1.0 - k)), 1.1 - k, [C[3], C[5], Ht[2], Ht[3]], func(g): return sin(g) < 0.0)
	var fw := 6.0 + 16.0 * Px.smooth(0.0, 0.8, t)
	var x := floori(-fw)
	while x <= fw:
		var u := absi(x) / fw
		var a := sqrt(1.0 - u) * Px.smooth(0.0, 0.4, t) * (1.0 - Px.smooth(WILT, WILT + 0.6, t))
		p.dot(x, 0.0, C[6] if u < 0.3 else (C[5] if u < 0.65 else C[4]), a)
		if (x % 5) == 0:
			p.glow(x, 0.0, 8.0, C[5], 0.2 * a * (1.0 - u))
		x += 1
	# the far petals sit behind the heart
	if t > BUD - 0.05:
		for q: Dictionary in petals:
			if sin(q.az) < 0.0 and not q.gone:
				petal(p, q, top)
	ps.draw(p, "back")


func draw(p: Px.Painter) -> void:
	var pts := stem()
	var top: Array = pts[12]
	var g := grow()
	if g > 0.02:
		# the stem: a 2 px shoot, lit down its left side
		for i in range(1, pts.size()):
			var x0: float = pts[i - 1][0]
			var y0: float = pts[i - 1][1]
			var x1: float = pts[i][0]
			var y1: float = pts[i][1]
			if y1 > 0.0:
				continue
			p.line(x0, y0, x1, y1, C[5])
			p.line(x0 + 1.0, y0, x1 + 1.0, y1, C[3])
		# leaves unfurl off it
		for lf: Array in [[4, -1.0, 0.1], [7, 1.0, 0.22]]:
			var i: int = lf[0]
			var sd: float = lf[1]
			var d: float = lf[2]
			var lk := Px.Ease.outBack(Px.clamp((t - d - 0.12) / 0.3), 1.6) * (1.0 - Px.smooth(WILT, WILT + 0.5, t) * 0.4)
			var x: float = pts[i][0]
			var y: float = pts[i][1]
			if lk <= 0.0 or y > -1.0:
				continue
			var la := -2.6 + 0.4 * (1.0 - lk) if sd < 0.0 else -0.55 - 0.4 * (1.0 - lk)
			Lib.drawLeaf(p, x + cos(la) * 6.0 * lk, y + sin(la) * 6.0 * lk, 12.0 * lk, 3.4, la, 0.25, [C[1], C[3], C[5], C[6]])
		# the bud, then the heart once it opens
		if t > STEM - 0.1 and t < OPEN - 0.1:
			var b := Px.clamp((t - STEM + 0.1) / (BUD - STEM))
			var w := 2.0 + 2.5 * b
			var h := 3.5 + 5.0 * b
			p.ellipse(top[0], top[1] - h * 0.6, w, h, func(d: float, a: float) -> int: return Pt[2] if cos(a) < -0.2 else (Pt[0] if d > 0.7 else Pt[1]))
			p.glow(top[0], top[1] - h * 0.6, 8.0 + 8.0 * b, Ht[2], 0.25 * b)
	for q: Dictionary in petals:
		if sin(q.az) >= 0.0 and not q.gone and t > BUD - 0.05:
			petal(p, q, top)
	if t > OPEN - 0.12 and t < WILT + 0.3:
		var pulse := 0.85 + 0.15 * sin(t * 9.0)
		var k := 1.0 - Px.smooth(WILT - 0.3, WILT + 0.3, t)
		var cy: float = top[1] - 4.0
		p.circle(top[0], cy, 3.3 * k, Ht[1])
		p.circle(top[0] - 0.5, cy - 0.5, 2.2 * k, Ht[2])
		p.px(top[0] - 1.0, cy - 1.0, Ht[3])
		p.glow(top[0], cy, 16.0 * pulse, Ht[2], 0.5 * k)
		p.glow(top[0], cy, 34.0, C[5], 0.2 * k)
	var e := t - OPEN + 0.12
	if e > 0.0 and e < 0.16:
		Px.sparkle(p, top[0], top[1] - 3.0, 10.0 * (1.0 - e / 0.16), Ht[3], Ht[2], 0.6)
	for q: Dictionary in flying:
		Lib.drawLeaf(p, q.x, q.y, 6.0, 2.2, q.a, q.fl, [Pt[0], Pt[1], Pt[2], Pt[3]], minf(1.0, q.life / 0.3))
	for q: Dictionary in glyphs:
		var k: float = (t - q.t0) / q.life
		cross(p, q.x + sin(k * 5.0 + q.seed) * 2.0, q.y - k * 24.0, q.L, C, sin(PI * k), sin(k * 14.0 + q.seed) > 0.8)
	ps.draw(p, "front")
	lights.draw(p)


# a petal: from closed round the bud to splayed open round the heart, foreshortened by where it points
func petal(p: Px.Painter, q: Dictionary, top: Array) -> void:
	var op := open()
	var e := Px.lerp(0.15, PI / 2.0 - 0.2, op)
	var dx: float = sin(e) * cos(q.az)
	var dz: float = sin(e) * sin(q.az)
	var dy := -cos(e)
	var L := Px.lerp(8.0, 12.0, op)
	var len := L * Px.hypot(dx, dy)
	var ang := atan2(dy, dx)
	var back := dz < 0.0
	var cy: float = top[1] - 3.0
	if len < 1.5:
		return
	Lib.drawLeaf(p, top[0] + dx * L * 0.5, cy + dy * L * 0.5, len + 1.0, 3.0 + (1.0 - absf(dz)) * 0.8, ang, 0.9 if back else 0.2, [Pt[0], Pt[0], Pt[1], Pt[2]] if back else [Pt[0], Pt[1], Pt[2], Pt[3]])
