# The stepped leader, the stroke flicker, the cooling channel and the scorch follow Sprite Fusion's open-source
# lightning (https://www.spritefusion.com/pixel-art-vfx/lightning), MIT License, Copyright (c) 2026 Hugo Duprez.
# port-of: src/fx/lightning/lightning-strike.js@252bdc884409f10453f6b2c4a7d39459300a3086
extends "../../core/effect.gd"

const Px := preload("../../core/px.gd")
const Lib := preload("_lib.gd")
const P := Px.P
const WHITE := Px.WHITE

static var meta := {
	"name": "Lightning strike",
	"desc": "A targeted strike: a sigil charges on the floor, the scene darkens, a thick bolt slams into it, arcs race out along the cracks it splits, the channel crumbles to a scorch.",
	"tags": ["lightning", "electric", "strike", "spell", "target", "impact", "ground", "one-shot"],
	"size": [240, 264],
	"origin": [120, 228],
	"duration": 3.0,
	"loop": false,
	"fps": 30,
	"bg": "ground",
	"options": {"palette": Lib.VOLT, "sparks": Lib.PLASMA, "seed": 5},
}

const W := 120.0
const TOP := -224.0
const RX := 28.0
const SY := 0.22
const REACH := 52.0
const LEAD0 := 0.48
const STEPS := 9.0
const MEET := -30.0
const STROKES := [{"t": 0.76, "k": 1.0}, {"t": 1.04, "k": 0.8}, {"t": 1.26, "k": 0.55}]
const FLICK := [1.0, 0.72, 0.3, 0.95, 0.5, 0.8, 0.22]
static func level(a: float) -> float:
	if a < 0.0:
		return 0.0
	var i := floori(a * 30.0 + 1e-4)
	return FLICK[i] if i < FLICK.size() else 0.0
static var NIGHT := Px.hex("#04030a")
static var DUST := Px.hex("#6e6382")
static var ASH := Px.hex("#5b5566")
static var STONE := Px.ramp(["#655b7a", "#4a4263", "#342d45"])
static var S1: float = STROKES[0].t


# the cracks the strike splits in the floor: Lichtenberg branches lying on the floor's face
static func cracks(R: Px.Rng) -> Array:
	var out := []
	for i in 6:
		grow(R, out, R.range(-1.0, 1.0), R.range(0.0, 1.0), R.range(-0.5, 0.7) if i % 2 else PI + R.range(-0.7, 0.5), REACH * R.range(0.55, 1.0), 1.0, 0.0, 0)
	return out


static func grow(R: Px.Rng, out: Array, x: float, y: float, a: float, ln: float, w: float, d: float, depth: int) -> void:
	var pts := [[x, y, d]]
	var s := 0.0
	while s < ln:
		a += R.range(-0.32, 0.32)
		x += cos(a) * 1.5
		y = Px.clamp(y + sin(a) * 0.45, 0.0, 5.0)
		d += 1.5
		pts.append([x, y, d])
		if depth < 2 and s > 3.0 and R.chance(0.09):
			grow(R, out, x, y, a + R.sign() * R.range(0.5, 1.2), (ln - s) * R.range(0.3, 0.6), w * 0.6, d, depth + 1)
		s += 1.5
	out.append({"pts": pts, "w": w})


# the sigil on the floor: a ring of dashes turning slowly, crosshair ticks, an inner ring and a heart; drawn in
# from the front, charging brighter; half picks the far (behind) or near part
static func sigil(p: Px.Painter, t: float, C: Array, k: float, near: bool) -> void:
	var reveal := Px.clamp(t / 0.22)
	var spin := t * 0.8
	var burnt := t - S1 if t > S1 else -1.0
	if burnt > 0.45:
		return
	var a0 := 1.0 if burnt < 0.0 else (1.0 if burnt < 0.07 else 1.0 - (burnt - 0.07) / 0.38)
	var hot := burnt >= 0.0 and burnt < 0.07
	var on := func(a: float) -> bool: return (sin(a) >= 0.0) == near
	var from := func(a: float) -> float: return absf(fmod(fmod(a - PI / 2.0, TAU) + TAU + PI, TAU) - PI) / PI
	for i in 22:
		var a := (i / 22.0) * TAU + spin
		if not on.call(a) or from.call(a) > reveal:
			continue
		for da: float in [0.0, 0.06, 0.12]:
			var x := cos(a + da) * RX
			var y := sin(a + da) * RX * SY
			p.dot(x, y, WHITE if hot else (((C[6] if k > 0.7 else C[5])) if near else (C[4] if k > 0.7 else C[3])), a0)
			if near:
				p.dot(x, y + 1.0, C[6] if hot else C[2], a0)
		if i % 3 == 0:
			p.glow(cos(a) * RX, sin(a) * RX * SY, 5.0, C[4], 0.3 * k * a0)
	for j in 4:
		var a := spin * -0.5 + (j * TAU) / 4.0 + PI / 4.0
		if not on.call(a) or reveal < 1.0:
			continue
		p.line(cos(a) * (RX - 5.0), sin(a) * (RX - 5.0) * SY, cos(a) * (RX + 5.0), sin(a) * (RX + 5.0) * SY, WHITE if hot else (C[6] if near else C[4]), a0)
	if t > 0.3:
		var a := 0.0
		while a < TAU:
			if not on.call(a):
				a += 0.09
				continue
			p.dot(cos(a) * 14.0, sin(a) * 14.0 * SY, WHITE if hot else (C[4] if near else C[2]), a0 * Px.clamp((t - 0.3) / 0.12))
			a += 0.09
	if near and burnt < 0.0:
		var pulse := 0.6 + 0.4 * sin(t * (10.0 + 30.0 * k))
		p.px(0.0, 0.0, WHITE if k > 0.5 else C[6])
		for dd: Array in [[1, 0], [-1, 0], [0, -1]]:
			p.px(dd[0], dd[1], C[5])
		p.glow(0.0, -1.0, 10.0 + 10.0 * k, C[5], 0.3 + 0.4 * k * pulse)


# keep forks on the canvas and above the floor
static func keep(b: Dictionary) -> Dictionary:
	var paths := []
	for q: Dictionary in b.paths:
		var pts := []
		for pt: Array in q.pts:
			if absf(pt[0]) > W - 5.0 or pt[1] > -3.0 or pt[1] < TOP + 6.0:
				break
			pts.append(pt)
		if q.w >= 1.0 or pts.size() > 3:
			paths.append({"w": q.w, "pts": q.pts if q.w >= 1.0 else pts})
	return {"paths": paths}


var o: Dictionary
var C: Array
var R: Px.Rng
var ps: Px.Particles
var hot: Px.Particles
var lights: Px.Lights
var X0: float
var main: Dictionary
var trunk: Array
var bolts: Array
var last: Dictionary
var end: Array
var tree: Array
var gone: Array
var t := 0.0
var struck := -1


func create(o_: Dictionary) -> void:
	o = o_
	C = Px.fit(o.palette, 8)
	R = Px.Rng.new(o.seed)
	var floor_ := func(): return 0.0
	ps = Px.Particles.new({"rng": R, "ground": floor_, "sparks": o.sparks})
	hot = Px.Particles.new({"rng": R, "ground": floor_})
	lights = Px.Lights.new()
	X0 = R.range(8.0, 18.0) * (1.0 if R.chance(0.5) else -1.0)
	main = keep(Lib.zigzag(R, X0, TOP, 0.0, -1.0, 0.17, 0.5))
	trunk = main.paths[0].pts
	var drift := func(dx: float) -> Callable: return func(x, y): return [x + dx * sin((PI * y) / TOP), y]
	bolts = [main, Lib.bend({"paths": [{"pts": trunk, "w": 1.0}]}, drift.call(1.5)), Lib.bend({"paths": [{"pts": trunk, "w": 1.0}]}, drift.call(3.0))]
	last = STROKES[STROKES.size() - 1]
	end = chan(STROKES.size() - 1)
	tree = cracks(R)
	# the spent channel breaks up from the top down, each piece at its own moment
	gone = []
	for i in end.size():
		var y: float = end[i][1]
		gone.append(last.t + 0.25 + 0.75 * (0.55 * Px.rand(o.seed, i, 5) + 0.45 * (1.0 - y / TOP)))


func chan(i: int) -> Array:
	return bolts[i].paths[0].pts


func now() -> Variant:
	var i := STROKES.size() - 1
	while i >= 0:
		if t >= STROKES[i].t:
			return {"i": i, "s": STROKES[i], "a": t - STROKES[i].t, "k": level(t - STROKES[i].t) * STROKES[i].k}
		i -= 1
	return null


func charge() -> float:
	return Px.clamp(t / S1) ** 1.5


func heatAt() -> float:
	if struck < 0:
		return 0.0
	var m := -INF
	for s: Dictionary in STROKES.slice(0, struck + 1):
		m = maxf(m, s.k * pow(Px.clamp(1.0 - (t - s.t) / 1.6), 1.4))
	return m


func update(dt: float) -> void:
	t += dt
	for i in STROKES.size():
		var s: Dictionary = STROKES[i]
		if struck >= i or t < s.t:
			continue
		struck = i
		var k: float = s.k
		lights.add(0.0, -50.0, 120.0, C[4], 0.55 * k, 0.4)
		lights.add(0.0, -3.0, 24.0, WHITE, 0.5 * k, 0.1)
		for j in Px.roundi(44.0 * k):
			var a := -PI / 2.0 + R.range(-1.3, 1.3)
			var sp := R.range(110.0, 320.0) * (0.65 + 0.35 * k)
			ps.spawn(P.SPARK, R.range(-1.5, 1.5), -2.0, cos(a) * sp, sin(a) * sp, R.range(0.2, 0.55))
		for j in Px.roundi(12.0 * k):
			var a := -PI / 2.0 + R.range(-1.2, 1.2)
			var sp := R.range(70.0, 220.0)
			hot.spawn(P.SPARK, R.range(-2.0, 2.0), -1.0, cos(a) * sp, sin(a) * sp, R.range(0.5, 1.0))
		for j in Px.roundi(5.0 * k):
			hot.spawn(P.EMBER, R.range(-4.0, 4.0), -2.0, R.range(-25.0, 25.0), -R.range(30.0, 80.0), R.range(0.8, 1.5))
		for j in Px.roundi(18.0 * k):
			var a := -PI / 2.0 + R.range(-1.1, 1.1)
			var sp := R.range(50.0, 190.0)
			ps.spawn(P.GRIT, R.range(-3.0, 3.0), -1.0, cos(a) * sp, sin(a) * sp, R.range(1.0, 1.5), R.pick(STONE), 2.0 if R.chance(0.35) else 1.0)
		for j in 8:
			ps.spawn(P.DUST, R.range(-3.0, 3.0), -1.0, R.sign() * R.range(30.0, 110.0), -R.range(4.0, 24.0), R.range(0.4, 0.8), DUST, R.range(1.5, 3.0))
		for j in Px.roundi(4.0 * k):
			ps.spawn(P.SMOKE, R.range(-8.0, 8.0), -4.0, R.range(-10.0, 10.0), -R.range(10.0, 25.0), R.range(1.1, 1.6), Px.mix(ASH, C[2], 0.3), R.range(3.0, 6.0), R.range(0.05, 0.25))
	if struck >= 0 and t < 1.7 and R.chance(6.0 * dt):
		ps.spawn(P.SMOKE, R.range(-8.0, 8.0), -2.0, R.range(-4.0, 4.0), -R.range(9.0, 17.0), R.range(1.0, 1.3), 0, R.range(2.0, 3.5))
	for i in gone.size() - 1:
		if gone[i] <= t and gone[i] > t - dt and Px.rand(o.seed, i, 6) < 0.5:
			var x: float = end[i][0]
			var y: float = end[i][1]
			ps.spawn(P.MOTE, x, y, R.range(-8.0, 8.0), R.range(6.0, 22.0), R.range(0.4, 0.8), C[5] if R.chance(0.5) else C[4], R.range(0.5, 0.9))
	ps.update(dt)
	hot.update(dt)
	lights.update(dt)


func drawBack(p: Px.Painter) -> void:
	# the scene darkens a beat before the strike: a soft veil, deepest round the bolt's path, gone at the flash
	var dark := 0.5 * Px.smooth(0.46, 0.66, t) * (1.0 - Px.smooth(S1 - 0.01, S1 + 0.02, t))
	if dark > 0.01:
		for y in range(-228, 36):
			for x in range(-int(W), int(W)):
				var d := Px.hypot(x / W, (y + 96) / 132.0)
				var a := dark * (1.0 - Px.smooth(0.55, 1.0, d))
				if a > 0.01:
					p.blend(x + 0.5, y + 0.5, NIGHT, a)
	sigil(p, t, C, charge(), false)
	# the cracks: arcs race out along them white, they glow with heat, cool to soot and fade
	if struck >= 0:
		var s: Dictionary = now()
		var front := REACH * Px.Ease.outCubic(Px.clamp((t - S1) / 0.35))
		var T0 := heatAt()
		var fade := 1.0 - Px.smooth(2.3, 2.95, t)
		var elec: float = s.s.k * (1.0 - s.a / 0.14) if s.a < 0.14 else 0.0
		for br: Dictionary in tree:
			for pt: Array in br.pts:
				var x: float = pt[0]
				var y: float = pt[1]
				var d: float = pt[2]
				if d > front:
					break
				var q := d / REACH
				var n := Px.rand(Px.round(x * 2.0), Px.round(y * 2.0), 9)
				var fresh := d > front - 6.0 and front < REACH
				var T: float = T0 * (1.15 - q) * (0.8 if br.w < 1.0 else 1.0) - n * 0.25
				var hT := Lib.heat(T)
				var c: int = (WHITE if q < 0.5 else C[6]) if (fresh or (elec > 0.3 and n < 0.85)) else (hT if hT else Lib.SOOT2)
				p.dot(x, y + 1.0, Lib.SOOT, fade)
				p.dot(x, y, c, fade)
				if br.w >= 1.0 and d < 9.0:
					p.dot(x, y + 2.0, Lib.SOOT, fade)
				if (fresh or elec > 0.3) and (Px.roundi(d) & 3) == 0:
					p.glow(x, y, 7.0, C[5], 0.4)
				elif T > 0.2 and (Px.roundi(d) & 3) == 0:
					p.glow(x, y, 5.0, c, 0.2 * T)
		Lib.scorch(p, 0.0, 0.0, 12.0, T0, fade)
		if T0 > 0.0:
			p.glow(0.0, -2.0, 34.0, Lib.heat(0.55), 0.3 * T0)
	ps.draw(p, "back")
	hot.draw(p, "back")


func draw(p: Px.Painter) -> void:
	var s: Variant = now()
	var f := floori(t * 30.0 + 1e-4)
	var k := charge()
	sigil(p, t, C, k, true)
	# static rising off the charging sigil, more and more of it
	if t > 0.15 and t < S1:
		var r := Px.rng(o.seed, 61, f)
		for i in Px.roundi(1.0 + 4.0 * k):
			var a := r.range(0.0, TAU)
			var x := cos(a) * RX
			var y := sin(a) * RX * SY
			Lib.crackle(p, Lib.zigzag(r, x, y, x + r.range(-2.5, 2.5), y - r.range(4.0, 9.0) * (0.6 + k), 0.45, 0.3), 0.45 + 0.4 * k, C, 0.3)
		p.glow(0.0, -2.0, 36.0, C[4], 0.12 + 0.3 * k)
	# the stepped leader feels down from above; a streamer climbs out of the sigil to meet it
	if t >= LEAD0 and t < S1:
		var u := Px.clamp((t - LEAD0) / (S1 - LEAD0))
		var st := minf(STEPS, floorf(u * STEPS) + 1.0)
		var fresh := 1.0 - fmod(u * STEPS, 1.0)
		var reach := TOP + (MEET - TOP) * pow(st / STEPS, 1.2)
		var prev := TOP + (MEET - TOP) * pow((st - 1.0) / STEPS, 1.2)
		for q: Dictionary in main.paths:
			var tk: bool = q.w >= 1.0
			var qp: Array = q.pts
			for i in qp.size() - 1:
				var ax: float = qp[i][0]
				var ay: float = qp[i][1]
				var bx: float = qp[i + 1][0]
				var by: float = qp[i + 1][1]
				if by > reach:
					if ay <= reach and i > 0:
						p.px(ax, ay, WHITE)
						p.glow(ax, ay, 7.0, C[5], 0.5 * fresh + 0.15)
					break
				var young := by > prev
				p.line(ax, ay, bx, by, (((C[6] if tk else C[5]) if fresh > 0.4 else C[4])) if young else (C[3] if tk else C[2]))
				if i % 4 == 0 and ay > TOP + 14.0:
					p.glow(ax, ay, 8.0 if young else 5.0, C[4], 0.3 * fresh + 0.1 if young else 0.12)
		if t > 0.62:
			var h := -MEET * Px.Ease.outQuad((t - 0.62) / (S1 - 0.62))
			var r := Px.rng(o.seed, 77, f)
			var b := Lib.zigzag(r, 0.0, -1.0, r.range(-2.0, 2.0), -maxf(3.0, h), 0.3, 0.3)
			var tip: Array = b.paths[0].pts.back()
			Lib.crackle(p, b, 0.85, C, 0.45)
			p.px(tip[0], tip[1], WHITE)
			p.glow(tip[0], tip[1], 9.0, C[5], 0.5)
	# the strokes, the dart that runs down the channel before each flicker, the channel cooling and crumbling
	var ni := -1
	for q in STROKES.size():
		if STROKES[q].t > t:
			ni = q
			break
	if ni >= 0 and ni != 0 and t > STROKES[ni].t - 0.06:
		var next: Dictionary = STROKES[ni]
		var tr := chan(ni)
		var u: float = (t - (next.t - 0.06)) / 0.06
		var i1 := floori(u * tr.size())
		Lib.trace(p, tr, C[3], 1.0)
		Lib.trace(p, tr, C[6], 1.0, i1 - 18, i1)
		var i := maxi(0, i1 - 18)
		while i < mini(tr.size(), i1):
			if tr[i][1] > TOP + 14.0:
				p.glow(tr[i][0], tr[i][1], 9.0, C[4], 0.35)
			i += 4
	elif s and s.k > 0.0:
		var hero: bool = s.i == 0 and s.a < 1.0 / 30.0
		Lib.stroke(p, bolts[s.i], s.k, C, 1.5 if s.i == 0 else 1.2, {"hero": hero, "core": ((1.2 if hero else 0.8)) if s.k > 0.6 else 0.0, "minY": TOP + 14.0})
		var r: float = 4.5 * s.k
		p.circle(0.0, -1.0, r + 1.5, C[2])
		p.circle(0.0, -1.0, r + 0.5, C[5])
		p.circle(0.0, -1.0, r * 0.65, WHITE)
		if s.a < 0.07:
			Px.sparkle(p, 0.0, -2.0, Px.round(12.0 * s.k * (1.0 - s.a / 0.07)), C[6], C[4], 0.25)
		p.glow(0.0, -16.0, 96.0, C[3], 0.42 * s.k)
		p.glow(0.0, -3.0, 22.0, C[5], 0.3 * s.k)
		if hero:
			p.glow(X0 * 0.5, -110.0, 170.0, C[3], 0.3)
	elif s:
		var crumble: bool = s.i == STROKES.size() - 1
		var cool := Px.clamp((s.a - 0.23) / 0.45)
		var tr := chan(s.i)
		for i in tr.size() - 1:
			if crumble and t >= gone[i]:
				continue
			var h := 1.0 - Px.clamp((t - last.t - 0.23) / (gone[i] - last.t - 0.23)) if crumble else 1.0 - cool
			p.line(tr[i][0], tr[i][1], tr[i + 1][0], tr[i + 1][1], C[5] if h > 0.7 else (C[4] if h > 0.4 else (C[3] if h > 0.15 else C[2])))
			if i % 6 == 0 and h > 0.3 and tr[i][1] > TOP + 14.0:
				p.glow(tr[i][0], tr[i][1], 6.0, C[4], 0.15 * h)
	# arcs crawl out along the cracks as they split, and again with every flicker
	if s and s.a < 0.4:
		var r := Px.rng(o.seed, 91, f)
		var run: float = REACH * Px.Ease.outCubic(Px.clamp(s.a / 0.35)) if s.i == 0 else REACH * Px.clamp(s.a / 0.22)
		for br: Dictionary in tree:
			if br.w < 1.0 or r.next() < 0.3:
				continue
			var bp: Array = br.pts
			var i1 := -1
			for q in bp.size():
				if bp[q][2] > run:
					i1 = q
					break
			var j1 := bp.size() if i1 < 0 else i1
			var j0 := maxi(0, j1 - r.int_(7, 13))
			var pts := []
			for pt: Array in bp.slice(j0, j1):
				var px: float = pt[0] + r.range(-0.6, 0.6)
				var py: float = pt[1] - 1.5 - r.range(0.0, 2.5)
				pts.append([px, py])
			if pts.size() > 1:
				Lib.crackle(p, {"paths": [{"pts": pts, "w": 1.0}]}, 0.9 * (1.0 - s.a / 0.4) + 0.1, C, 0.35)
	ps.draw(p, "front")
	hot.draw(p, "front")
	lights.draw(p)
