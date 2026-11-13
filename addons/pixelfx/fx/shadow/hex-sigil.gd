# port-of: src/fx/shadow/hex-sigil.js@8452c54739a41e7dce5a253dc6932391b65fde2c
extends "../../core/effect.gd"

const Px := preload("../../core/px.gd")
const Lib := preload("_lib.gd")
const P := Px.P
const B := Px.B
const PK := Lib.PK
const WHITE := Px.WHITE

static var meta := {
	"name": "Hex sigil",
	"desc": "A burning pen traces a cursed sigil in the air, its glyphs pop in one by one, then it flares white and crumbles into falling embers.",
	"tags": ["shadow", "hex", "sigil", "rune", "curse", "magic", "circle", "one-shot"],
	"size": [168, 128],
	"origin": [84, 112],
	"duration": 4.2,
	"loop": false,
	"fps": 30,
	"bg": "ground",
	"options": {"palette": Lib.VOID, "seed": 7},
}

# the sigil's centre and radii; the beats: traced, glyphs pop, holds, flares, crumbles
const CY := -50.0
const RO := 28.0
const RI := 22.0
const RC := 6.0
const GLYPH := 1.62
const FLARE := 2.6
const BREAK := 2.74


static func circle(r: float, a0: float, n: int = 0) -> Array:
	var m: int = n if n else ceili(r * TAU)
	var out := []
	for i in m + 1:
		out.append([cos(a0 + (i / float(m)) * TAU) * r, CY + sin(a0 + (i / float(m)) * TAU) * r])
	return out


# the strokes, in the order the pen draws them, as points with the moment the pen passes each
static func strokes(_seed: Variant) -> Dictionary:
	var paths := []
	paths.append(circle(RO, -PI / 2.0))
	# a seven-pointed star, drawn in one stroke, three points round each time
	var star := []
	for i in 8:
		var a := -PI / 2.0 + ((i * 3) % 7) * (TAU / 7.0)
		star.append([cos(a) * RI, CY + sin(a) * RI])
	paths.append(star)
	paths.append(circle(RI, -PI / 2.0))
	paths.append(circle(RC, PI / 2.0))
	paths.append([[0.0, CY - 3.5], [2.0, CY], [0.0, CY + 3.5], [-2.0, CY], [0.0, CY - 3.5]])
	# sample every half pixel, timing the pen along it: the outer circle fast, the star with more weight
	var pts := []
	var speeds := [420.0, 700.0, 550.0, 380.0, 300.0]
	var t := 0.12
	for k in paths.size():
		var path: Array = paths[k]
		for i in range(1, path.size()):
			var x0: float = path[i - 1][0]
			var y0: float = path[i - 1][1]
			var x1: float = path[i][0]
			var y1: float = path[i][1]
			var L := Px.hypot(x1 - x0, y1 - y0)
			var d := 0.0
			while d < L:
				pts.append({"x": x0 + ((x1 - x0) * d) / L, "y": y0 + ((y1 - y0) * d) / L, "t": t + d / speeds[k]})
				d += 0.5
			t += L / speeds[k]
		t += 0.04
	return {"pts": pts, "end": t}


# seven small glyphs of our own: a spine and two or three branches on a 3x3 grid of nodes
static func glyphs(seed: Variant) -> Array:
	return Px.arr(7, func(i):
		var r := Px.rng(seed, i, 31)
		var segs := [[[1, 0], [1, 2]]]
		var k := 0
		while k < 2 + (1 if r.next() < 0.5 else 0):
			var a := [r.int_(0, 2), r.int_(0, 2)]
			var b := [maxi(0, mini(2, a[0] + r.int_(-1, 1))), maxi(0, mini(2, a[1] + r.int_(-1, 1)))]
			if a[0] != b[0] or a[1] != b[1]:
				segs.append([a, b])
			k += 1
		var ang: float = -PI / 2.0 + (i * TAU) / 7.0 + PI / 7.0
		var rr := (RO + RI) / 2.0
		return {"x": cos(ang) * rr, "y": CY + sin(ang) * rr, "segs": segs, "t": GLYPH + i * 0.07})


var C: Array
var R: Px.Rng
var S: Dictionary
var G: Array
var ps: Px.Particles
var embers: Px.Particles
var puffs: Lib.Puffs
var bits: Px.Bits
var lights: Array = []
var t := 0.0
var pi := 0
var flared := false
var broke := false


func create(o: Dictionary) -> void:
	C = Px.fit(o.palette, 8)
	R = Px.Rng.new(o.seed)
	var floor_ := func(): return 0.0
	S = strokes(o.seed)
	G = glyphs(o.seed)
	ps = Px.Particles.new({"rng": R, "ground": floor_, "sparks": [WHITE, C[7], C[6], C[5]]})
	embers = Px.Particles.new({"rng": R, "ground": floor_, "sparks": [C[7], C[6], C[5], C[4]]})
	puffs = Lib.Puffs.new({"rng": R, "flame": [WHITE, C[7], C[6], C[5], C[4], C[3], C[2], C[1], C[0]], "soot": [Px.mix(C[3], C[2], 0.5), Px.mix(C[2], C[1], 0.5)], "cap": Px.mix(C[4], C[2], 0.5), "rim": [C[6], C[5], C[4]], "floor": floor_})
	bits = Px.Bits.new({"ground": floor_})
	lights = []
	t = 0.0
	pi = 0
	flared = false
	broke = false


func pen() -> Dictionary:
	return S.pts[mini(S.pts.size() - 1, pi)]


func update(dt: float) -> void:
	t += dt
	# the pen: it spits sparks and drips burning embers as it writes
	while pi < S.pts.size() - 1 and S.pts[pi + 1].t <= t:
		pi += 1
	if t > 0.12 and t < S.end:
		var q := pen()
		if R.chance(dt * 70.0):
			ps.spawn(P.SPARK, q.x, q.y, R.range(-70.0, 70.0), R.range(-100.0, 20.0), R.range(0.12, 0.35))
		if R.chance(dt * 10.0):
			embers.spawn(P.EMBER, q.x, q.y, R.range(-12.0, 12.0), R.range(5.0, 25.0), R.range(0.5, 0.9))
	# power drawn into the sigil while it's written and held: streaks racing in to its heart
	if t > 0.2 and t < FLARE - 0.05 and R.chance(dt * (8.0 + 14.0 * Px.smooth(0.2, FLARE, t))):
		var a := R.range(0.0, TAU)
		var D0 := R.range(40.0, 60.0)
		var T := R.range(0.22, 0.32)
		var v := (D0 * 3.0) / (exp(3.0 * T) - 1.0)
		ps.spawn(P.STREAK, cos(a) * D0, CY + sin(a) * D0, -cos(a) * v, -sin(a) * v, T, C[7] if R.chance(0.5) else C[6])
	for g: Dictionary in G:
		if not g.get("popped", false) and t >= g.t:
			g.popped = true
			lights.append({"x": g.x, "y": g.y, "r": 14.0, "k": 0.7, "life": 0.2, "max": 0.2})
			for i in 4:
				ps.spawn(P.SPARK, g.x, g.y, R.range(-60.0, 60.0), R.range(-70.0, 20.0), R.range(0.1, 0.25))
	if t >= FLARE and not flared:
		flared = true
		lights.append({"x": 0.0, "y": CY, "r": 96.0, "k": 1.4, "life": 0.45, "max": 0.45})
		lights.append({"x": 0.0, "y": CY, "r": 44.0, "k": 1.0, "life": 0.14, "max": 0.14})
		for i in 24:
			var a := R.range(0.0, TAU)
			var sp := R.range(60.0, 130.0)
			ps.spawn(P.SPARK, cos(a) * 13.0, CY + sin(a) * 13.0, cos(a) * sp, sin(a) * sp - 30.0, R.range(0.2, 0.45))
	if t >= BREAK and not broke:
		# it crumbles: every stroke breaks into burning fragments that tumble down and bounce
		broke = true
		# pieces drop nearly straight at first, so the sigil's shape lingers as it falls apart
		var i := 0
		while i < S.pts.size() - 1:
			var q: Dictionary = S.pts[i]
			var n: Dictionary = S.pts[i + 1]
			var a := atan2(n.y - q.y, n.x - q.x)
			bits.add({"kind": B.SHARD, "x": q.x, "y": q.y, "vx": R.range(-8.0, 8.0), "vy": R.range(-12.0, 6.0), "g": R.range(0.22, 0.45), "drag": 0.6, "bounce": 0.25, "life": R.range(0.8, 1.2), "a": a, "va": R.range(-3.0, 3.0), "s": R.range(2.5, 3.5), "c": R.pick([C[7], C[6], C[6], C[5]])})
			if i % 27 == 0:
				embers.spawn(P.EMBER, q.x, q.y, R.range(-10.0, 10.0), -R.range(10.0, 40.0), R.range(0.6, 1.1))
			i += 7
		for g: Dictionary in G:
			puffs.spawn(PK.SOOT, g.x, g.y, R.range(-6.0, 6.0), -R.range(8.0, 18.0), R.range(0.7, 1.1), R.range(3.0, 5.0))
		for j in 8:
			puffs.spawn(PK.SOOT, R.range(-20.0, 20.0), CY + R.range(-20.0, 20.0), R.range(-8.0, 8.0), -R.range(6.0, 16.0), R.range(0.8, 1.2), R.range(3.0, 6.0), R.range(0.0, 0.15))
	for i in range(lights.size() - 1, -1, -1):
		lights[i].life -= dt
		if lights[i].life <= 0.0:
			lights.remove_at(i)
	bits.update(dt)
	ps.update(dt)
	embers.update(dt)
	puffs.update(dt)


func drawBack(p: Px.Painter) -> void:
	puffs.draw(p, PK.SOOT, {"x": 0.0, "y": CY, "k": 0.3 if broke else 0.0, "reach": 50.0})
	var k := Px.smooth(0.1, 0.6, t) if t < BREAK else 1.0 - Px.smooth(BREAK, BREAK + 0.6, t)
	if k > 0.0:
		p.glow(0.0, CY, 52.0, C[4], 0.3 * k)


func draw(p: Px.Painter) -> void:
	if not broke:
		# the traced lines: white where the pen just passed, cooling to violet; pulsing as it holds; white in the flare
		var hold: float = 0.5 + 0.5 * sin((t - S.end) * 9.0) if t > S.end else 0.0
		var white := t >= FLARE
		for q: Dictionary in S.pts:
			if q.t > t:
				break
			var age: float = t - q.t
			p.px(q.x, q.y, WHITE if white else (WHITE if age < 0.05 else (C[7] if age < 0.15 else (C[6] if age < 0.35 else (C[6] if hold > 0.75 else C[5])))))
		if white:
			for q: Dictionary in S.pts:
				if Px.i32(q.x * 2.0) % 3 == 0:
					p.light(q.x, q.y, C[6], 0.5)
		# glyphs: each pops in white and settles
		for g: Dictionary in G:
			if t < g.t:
				continue
			var age: float = t - g.t
			var col: int = WHITE if (white or age < 0.06) else (C[7] if age < 0.2 else (C[7] if hold > 0.75 else C[6]))
			for sg: Array in g.segs:
				var a: Array = sg[0]
				var b: Array = sg[1]
				p.line(g.x - 2.0 + a[0] * 2, g.y - 2.0 + a[1] * 2, g.x - 2.0 + b[0] * 2, g.y - 2.0 + b[1] * 2, col)
			if age < 0.18:
				Lib.ringFast(p, g.x, g.y, 2.0 + 4.0 * (age / 0.18), 1.0, C[7] if age < 0.09 else C[5])
			p.glow(g.x, g.y, 6.0, C[5], 0.25)
		# the pen: a white-hot point with a little cross of light
		if t > 0.12 and t < S.end + 0.05:
			var q := pen()
			Px.sparkle(p, q.x, q.y, 3.0 + sin(t * 60.0), C[7], C[6], 0.6)
			p.glow(q.x, q.y, 16.0, C[6], 0.55)
	# the flare: a burst ring as it goes white
	var fu := (t - FLARE) / 0.35
	var bu := (t - FLARE) / 0.22
	if bu > 0.0 and bu < 1.0:
		Px.sparkle(p, 0.0, CY, 18.0 * (1.0 - bu), C[7], C[5], 0.9 * (1.0 - bu))
	if fu > 0.0 and fu < 1.0:
		Lib.ringFast(p, 0.0, CY, RO + 3.0 + 12.0 * Px.Ease.outCubic(fu), maxf(1.0, 3.0 * (1.0 - fu)), WHITE if fu < 0.4 else (C[6] if fu < 0.7 else C[4]))
	bits.draw(p)
	puffs.draw(p, PK.FLAME)
	ps.draw(p)
	embers.draw(p)
	for l: Dictionary in lights:
		var q: float = l.life / l.max
		p.glow(l.x, l.y, l.r * (0.6 + 0.4 * q), C[5] if l.k > 1.0 else C[6], l.k * q * q)
