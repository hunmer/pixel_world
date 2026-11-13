# The lip's crescent (a thick arc, white on its outer rim, cooling to deep blue underneath, with light along it)
# follows Sprite Fusion's open-source slash (https://www.spritefusion.com/pixel-art-vfx/slash),
# MIT License, Copyright (c) 2026 Hugo Duprez.
# port-of: src/fx/water/wave-crash.js@4a22114c1c405fd0c905b5bdad91eb2418808004
extends "../../core/effect.gd"

const Px := preload("../../core/px.gd")
const Lib := preload("_lib.gd")
const P := Px.P
const WHITE := Px.WHITE

static var meta := {
	"name": "Wave crash",
	"desc": "A swell rolls in and steepens, its lip throws forward and curls over a dark barrel, then crashes into a burst of white foam and spray that surges on and fades to lace.",
	"tags": ["water", "wave", "crash", "surf", "foam", "spray", "one-shot"],
	"size": [224, 104],
	"origin": [112, 86],
	"duration": 3.2,
	"loop": false,
	"fps": 30,
	"bg": "ground",
	"options": {"palette": Lib.WATER, "seed": 6},
}

const SY := 0.22
const G := 820.0
const CRASH := 1.2
const LIP0 := 0.62
const EDGE := 110


# the swell: where its crest is, how tall, how steep its face, as it rolls in, crashes and runs on as whitewater
static func crestX(t_: float) -> float:
	return -80.0 + 72.0 * Px.Ease.inOutSine(t_ / CRASH) if t_ < CRASH else -8.0 + 30.0 * Px.Ease.outCubic(Px.clamp((t_ - CRASH) / 1.4))


static func crestH(t_: float) -> float:
	return 5.0 + 33.0 * Px.Ease.inOutSine(Px.clamp(t_ / (CRASH * 0.92))) if t_ < CRASH else 38.0 * (1.0 - Px.Ease.outCubic(Px.clamp((t_ - CRASH) / 0.45))) + 5.0 * (1.0 - Px.smooth(CRASH, CRASH + 1.6, t_))


static func faceW(t_: float) -> float:
	return 24.0 - 16.0 * Px.smooth(0.3, CRASH, t_) if t_ < CRASH else 8.0 + 14.0 * Px.smooth(CRASH, CRASH + 0.6, t_)


# the lip: thrown forward off the crest and falling, until its tip hits the water at CRASH
static func lipK(t_: float) -> float:
	return Px.clamp((t_ - LIP0) / (CRASH - LIP0))


static func height(x: float, tt: float) -> float:
	var xc := crestX(tt)
	var A := crestH(tt)
	var dx := x - xc
	return A * Px.exp(-(pow(dx / (30.0 if dx < 0.0 else faceW(tt)), 2.0)))


# a point on the lip at s (0 at the crest, 1 at its tip), and its thickness there
static func lip(s: float, tt: float) -> Array:
	var k := lipK(tt)
	var xc := crestX(tt)
	var A := crestH(tt)
	return [xc + 1.0 + s * 30.0 * pow(k, 0.8), -A - 4.0 * s * (1.0 - s) * (1.0 + 4.0 * k) + s * s * A * Px.Ease.inQuad(k) * 0.98, (11.0 - 8.5 * s) * (0.5 + 0.5 * k)]


var C: Array
var R: Px.Rng
var S: float
var ps: Px.Particles
var mist: Lib.Mist
var lights: Px.Lights
var rings: Lib.Ripples
var puffs: Array
var plinks: Array
var drops: Lib.Drops
var t := 0.0
var crashed := false


func create(o: Dictionary) -> void:
	C = Px.fit(o.palette, 8)
	R = Px.Rng.new(o.seed)
	S = o.seed
	ps = Px.Particles.new({"rng": R})
	mist = Lib.Mist.new()
	lights = Px.Lights.new()
	rings = Lib.Ripples.new({"sy": SY})
	puffs = []
	plinks = []
	drops = Lib.Drops.new({
		"sy": SY,
		"g": G,
		"onLand": func(d: Dictionary):
			rings.add(d.x, d.z, 0.6, 2.0 + d.s * 1.8, 0.3 + d.s * 0.1, {"n": 1.0, "k": 0.9, "hot": 0.05})
			plinks.append({"x": d.x, "y": d.z * SY, "age": 0.0}),
	})
	t = 0.0
	crashed = false


func puff(x: float, y: float, vx: float, vy: float, r0: float, r1: float, life: float, delay: float = 0.0) -> void:
	puffs.append({"x": x, "y": y, "vx": vx, "vy": vy, "r0": r0, "r1": r1, "life": life, "max": life, "delay": delay})


# the swell's body, column by column: deep blue down its back and base with wind lines, a lit rim along its
# surface, white water at the crest, a lit window high on its face where the light comes through, and streaks of
# foam drawn up the face
func body(p: Px.Painter, fade: float) -> void:
	var xc := crestX(t)
	var A := crestH(t)
	for X in range(-EDGE, EDGE):
		var x := X + 0.5
		var h := height(x, t)
		var edge := 1.0 - Px.smooth(EDGE - 24, EDGE, absf(x))
		if h < 0.6 or edge <= 0.0:
			continue
		var face := x > xc
		var near := Px.exp(-(pow((x - xc) / 9.0, 2.0)))
		var a := fade * edge * 1.4
		var Y := floorf(-h)
		while Y < 0.0:
			var y := Y + 0.5
			var u := (y + h) / h
			var depth := y + h
			var c: int
			if depth < 1.0:
				c = WHITE if (near > 0.5 and A > 14.0 and Px.noise(x * 0.6 + t * 9.0, S) > -0.35) else (C[5] if face else C[6])
			elif depth < 2.4 and near > 0.35 and A > 14.0:
				c = WHITE if Px.noise2(x * 0.5, y * 0.5 + t * 6.0, S + 1.0) > -0.1 else C[6]
			else:
				# face and back shade differently; blend the two across the crest so there's no seam
				var win := near * (1.0 - u) * 1.6
				var up := Px.noise2((x * 0.9 - y * 0.35) * 0.8, y * 0.12 + t * 5.0, S + 2.0)
				var wind := Px.noise2(x * 0.18 - t * 2.0, y * 0.9, S + 3.0)
				var fi := 6 if (up > 0.55 and u < 0.85) else (5 if win > 0.8 else (4 if (win > 0.45 or up > 0.3) else (3 if (win > 0.2 or up > 0.05) else (2 if u < 0.6 else 1))))
				var bi := 4 if u < 0.14 else (4 if wind > 0.55 else (3 if (wind > 0.25 or u < 0.32) else (2 if u < 0.7 else 1)))
				c = C[Px.roundi(bi + (fi - bi) * Px.smooth(xc - 5.0, xc + 5.0, x))]
			p.dot(X, Y, c, a)
			Y += 1.0


# the lip: a thick arc thrown off the crest, white along its outer edge, tinted through, dark underneath
func curl(p: Px.Painter) -> void:
	var k := lipK(t)
	if k <= 0.0 or t >= CRASH:
		return
	var cells := {}
	var s := 0.0
	while s <= 1.0:
		var l0 := lip(s, t)
		var x: float = l0[0]
		var y: float = l0[1]
		var w: float = l0[2]
		var l1 := lip(minf(1.0, s + 0.012), t)
		var x2: float = l1[0]
		var y2: float = l1[1]
		var tx := x2 - x
		var ty := y2 - y
		var l := Px.hypot(tx, ty)
		if not l:
			l = 1.0
		var nx := ty / l
		var ny := -tx / l
		var q := 0.0
		while q <= 1.0:
			var px := x + nx * (q - 0.5) * w
			var py := y + ny * (q - 0.5) * w
			var key := floori(py) * 1024 + floori(px)
			# q 0 is the outer (upper) rim, 1 the underside
			var c: int = WHITE if q < 0.18 else ((WHITE if s > 0.8 else C[6]) if q < 0.36 else (C[5] if q < 0.56 else (C[4] if q < 0.76 else C[3])))
			var cur: Variant = cells.get(key)
			if cur == null or q < cur.q:
				cells[key] = {"x": px, "y": py, "c": c, "q": q}
			q += 0.5 / maxf(1.0, w)
		s += 0.012
	for c: Dictionary in cells.values():
		p.px(c.x, c.y, c.c)
	s = 0.0
	while s <= 1.0:
		var l0 := lip(s, t)
		var x: float = l0[0]
		var y: float = l0[1]
		var w: float = l0[2]
		p.glow(x, y, 6.0 + w, C[5], 0.24 * k)
		s += 0.125
	# the tip glints as it throws
	var tip := lip(1.0, t)
	var tx: float = tip[0]
	var ty: float = tip[1]
	var g := sin(PI * Px.clamp((k - 0.55) / 0.45))
	if g > 0.05:
		Px.sparkle(p, tx, ty, 6.0 * g, C[6], C[5], 0.5 * g)
	# light caught under the barrel
	var b := lip(0.6, t)
	var bx: float = b[0]
	var by: float = b[1]
	p.glow(bx - 3.0, by + 8.0, 16.0, C[4], 0.25 * k)


# the sea it rolls on: a lit line along the surface, dark water under it, glints sliding along
func sea(p: Px.Painter, fade: float) -> void:
	for X in range(-EDGE, EDGE):
		var x := X + 0.5
		var edge := 1.0 - Px.smooth(EDGE - 30, EDGE, absf(x))
		var a := fade * edge
		if a <= 0.02:
			continue
		var g := Px.noise(x * 0.3 - t * 3.0, S + 4.0)
		p.dot(X, 0.0, C[6] if g > 0.55 else C[4], a * 1.2)
		p.blend(x, 1.5, C[2], 0.6 * a)
		p.blend(x, 2.5, C[1], 0.45 * a)


func update(dt: float) -> void:
	t += dt
	var k := lipK(t)
	# wind tears spray off the crest; the lip's tip sheds drops as it throws
	if t < CRASH and crestH(t) > 14.0 and R.chance(0.5):
		var xc := crestX(t)
		var A := crestH(t)
		ps.spawn(P.FLAKE, xc + R.range(-4.0, 3.0), -A - R.range(0.0, 2.0), -R.range(20.0, 60.0), -R.range(10.0, 40.0), R.range(0.5, 0.9), WHITE if R.chance(0.5) else C[6], R.range(0.6, 1.3))
	if k > 0.3 and t < CRASH and R.chance(0.35):
		var xy := lip(1.0, t)
		var x: float = xy[0]
		var y: float = xy[1]
		drops.add({"x": x, "z": R.range(-3.0, 3.0), "h": -y, "vx": R.range(30.0, 90.0), "vz": R.range(-10.0, 10.0), "vh": R.range(-20.0, 40.0), "s": 2.0 if R.chance(0.3) else 1.0})
	if not crashed and t >= CRASH:
		crashed = true
		var X0: float = lip(1.0, CRASH - 1e-3)[0]
		lights.add(X0, -20.0, 56.0, C[5], 0.8, 0.55)
		lights.add(X0, -4.0, 22.0, WHITE, 0.6, 0.1)
		for i in 46:
			var a := R.range(-0.9, 0.6) * PI
			var v := R.range(30.0, 120.0)
			drops.add({"x": X0 + R.range(-6.0, 6.0), "z": R.range(-4.0, 4.0), "h": R.range(2.0, 8.0), "vx": cos(a) * v * 0.85 + 18.0, "vz": sin(a) * v * 0.5, "vh": R.range(120.0, 320.0), "s": 3.0 if R.chance(0.15) else (2.0 if R.chance(0.35) else 1.0), "delay": R.range(0.0, 0.1)})
		# the spit: a plume shot straight up where the lip lands
		for i in 14:
			drops.add({"x": X0 + R.range(-3.0, 3.0), "z": R.range(-2.0, 2.0), "h": R.range(2.0, 6.0), "vx": R.range(-15.0, 25.0), "vz": R.range(-8.0, 8.0), "vh": R.range(220.0, 300.0), "s": 2.0 if R.chance(0.3) else 1.0, "delay": R.range(0.04, 0.16)})
		for i in 34:
			puff(X0 + R.range(-12.0, 10.0), -R.range(2.0, 12.0), R.range(-40.0, 130.0), -R.range(30.0, 150.0), R.range(1.0, 2.0), R.range(1.8, 4.2), R.range(0.4, 0.95), R.range(0.0, 0.14))
		# fine spray hangs in the air over the burst
		for i in 34:
			var a := R.range(-PI * 0.95, -PI * 0.05)
			var v := R.range(40.0, 160.0)
			ps.spawn(P.FLAKE, X0 + R.range(-8.0, 8.0), -R.range(4.0, 14.0), cos(a) * v + 25.0, sin(a) * v, R.range(0.6, 1.3), WHITE if R.chance(0.5) else C[6], R.range(0.6, 1.4), R.range(0.0, 0.1))
		for i in 12:
			mist.add(X0 + R.range(-10.0, 14.0), -R.range(3.0, 16.0), R.range(-20.0, 70.0), -R.range(6.0, 24.0), 3.0, R.range(9.0, 15.0), R.range(1.1, 1.7), C[6] if R.chance(0.5) else WHITE, 0.26, R.range(0.0, 0.2))
		for i in 10:
			ps.spawn(P.STAR, X0 + R.range(-20.0, 24.0), -R.range(6.0, 40.0), 0.0, -5.0, R.range(0.3, 0.6), C[6], R.range(1.0, 2.4), R.range(0.05, 0.4))
		rings.add(X0, 0.0, 6.0, 40.0, 1.2, {"n": 2.0, "gap": 3.0, "k": 1.1, "hot": 0.12})
	# the whitewater surges on, boiling up foam at its front, then calms
	if crashed and t < CRASH + 1.1 and R.chance(0.45 * (1.0 - (t - CRASH) / 1.1)):
		var x := crestX(t) + R.range(-6.0, 14.0)
		puff(x, -R.range(1.0, 4.0), R.range(10.0, 40.0), -R.range(10.0, 40.0), R.range(0.9, 1.8), R.range(1.8, 3.6), R.range(0.4, 0.8))
	if crashed and t < CRASH + 0.8 and R.chance(0.12):
		mist.add(crestX(t) + R.range(-8.0, 8.0), -R.range(2.0, 6.0), R.range(10.0, 40.0), -R.range(3.0, 10.0), 3.0, R.range(7.0, 11.0), R.range(0.8, 1.1), C[6], 0.2)
	var i := puffs.size() - 1
	while i >= 0:
		var f: Dictionary = puffs[i]
		if f.delay > 0:
			f.delay -= dt
			i -= 1
			continue
		f.life -= dt
		if f.life <= 0:
			puffs.remove_at(i)
			i -= 1
			continue
		f.vx -= f.vx * 2.5 * dt
		f.vy += (160.0 - f.vy * 2.5) * dt
		f.x += f.vx * dt
		f.y = minf(f.y + f.vy * dt, -1.0)
		i -= 1
	i = plinks.size() - 1
	while i >= 0:
		plinks[i].age += dt
		if plinks[i].age > 0.12:
			plinks.remove_at(i)
		i -= 1
	drops.update(dt)
	rings.update(dt)
	mist.update(dt)
	ps.update(dt)
	lights.update(dt)


func drawBack(p: Px.Painter) -> void:
	var fade := Px.smooth(0.0, 0.25, t) * (1.0 - Px.smooth(meta.duration - 0.7, meta.duration - 0.1, t))
	sea(p, fade)
	rings.draw(p, C, -1.0)
	drops.draw(p, C, "back")


func draw(p: Px.Painter) -> void:
	var fade := Px.smooth(0.0, 0.25, t) * (1.0 - Px.smooth(meta.duration - 0.7, meta.duration - 0.1, t))
	body(p, fade)
	curl(p)
	rings.draw(p, C, 1.0)
	# lace left on the water behind the surge, thinning out
	if crashed:
		var k := 1.0 - Px.smooth(CRASH + 0.4, meta.duration - 0.15, t)
		var x0 := -20.0
		var x1 := crestX(t) + 10.0
		var X := floorf(x0)
		while X < x1:
			var x := X + 0.5
			var n := 1.0 - absf(Px.noise2(x * 0.35, t * 0.8, S + 7.0)) * 4.0
			if n > 1.15 - k * 1.1:
				p.px(X, 0.0, WHITE if n > 1.4 - k else C[6])
			if n > 1.4 - k * 0.9:
				p.px(X, 1.0, C[5])
			X += 1.0
	for f: Dictionary in puffs:
		if f.delay > 0:
			continue
		var g: float = 1.0 - f.life / f.max
		var r: float = (f.r0 + (f.r1 - f.r0) * Px.Ease.outCubic(g)) * (1.0 - Px.smooth(0.7, 1.0, g))
		if r > 0.6:
			Lib.billow(p, f.x, f.y, r, C)
	for q: Dictionary in plinks:
		if q.age < 0.06:
			p.px(q.x, q.y, WHITE)
		p.glow(q.x, q.y, 4.0, C[5], 0.25 * (1.0 - q.age / 0.12))
	drops.draw(p, C, "front")
	# the crash: a white burst where the lip lands
	var f := (t - CRASH) / 0.08
	if f >= 0.0 and f < 1.0:
		var X0: float = lip(1.0, CRASH - 1e-3)[0]
		p.circle(X0, -3.0, 8.0 * (1.0 - f * 0.4), WHITE)
		p.ellipse(X0, 0.0, 14.0, 2.6, func(d: float): return WHITE if d < 0.6 else C[6])
	ps.draw(p)
	mist.draw(p, C[5])
	lights.draw(p)
	# light: the crest catches it while it stands, the whitewater after
	if t < CRASH:
		p.glow(crestX(t) + 4.0, -crestH(t) + 2.0, 26.0, C[4], 0.22 * Px.smooth(0.2, CRASH, t))
		p.glowLine(crestX(t) - 26.0, -crestH(t) * 0.45, crestX(t), -crestH(t), 10.0, C[5], 0.14 * Px.smooth(0.2, CRASH, t))
	else:
		p.glow(crestX(t), -10.0, 34.0, C[4], 0.26 * (1.0 - Px.smooth(CRASH, meta.duration - 0.3, t)))
