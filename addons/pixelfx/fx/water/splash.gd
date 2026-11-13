# The droplet recipe (shaded beads with tails that fly, land and throw up a little crown of their own) is
# adapted from Sprite Fusion's open-source blood (https://www.spritefusion.com/pixel-art-vfx/blood),
# MIT License, Copyright (c) 2026 Hugo Duprez.
# port-of: src/fx/water/splash.js@abb52499d80bcb461a33e8a94f2355dfe90c2bcc
extends "../../core/effect.gd"

const Px := preload("../../core/px.gd")
const Lib := preload("_lib.gd")
const P := Px.P
const WHITE := Px.WHITE

static var meta := {
	"name": "Splash",
	"desc": "A stone drops into still water: a white hit, a crown that tears into droplets arcing out to plink down with rings, a jet that bounces back, foam and drifting mist.",
	"tags": ["water", "splash", "impact", "drop", "liquid", "one-shot"],
	"size": [176, 100],
	"origin": [88, 78],
	"duration": 2.5,
	"loop": false,
	"fps": 30,
	"bg": "ground",
	"options": {"palette": Lib.WATER, "stone": true, "seed": 3},
}

const SY := 0.22
const HIT := 0.16
const G := 820.0
const FINGERS := 12
const JET := 0.3
const TEAR := 0.11


# the crown over time u after the hit: it leaps up in a few frames, flares out, then falls back
static func height(u: float) -> float:
	return 19.0 * Px.Ease.outCubic(Px.clamp(u / 0.09)) * (1.0 - Px.Ease.inQuad(Px.clamp((u - 0.12) / 0.3)))


static func foot(u: float) -> float:
	return 3.0 + 7.5 * Px.Ease.outCubic(Px.clamp(u / 0.45))


static func lip(u: float) -> float:
	return foot(u) + height(u) * 0.42 + 3.0 * Px.Ease.outCubic(Px.clamp(u / 0.25))


# the jet that bounces back up the middle once the crown has fallen
static func jetH(u: float) -> float:
	return 26.0 * (Px.Ease.outCubic(Px.clamp(u / 0.12)) - Px.Ease.inQuad(Px.clamp((u - 0.15) / 0.28)))


var o: Dictionary
var C: Array
var R: Px.Rng
var ST: Array
var phi: float
var ps: Px.Particles
var mist: Lib.Mist
var lights: Px.Lights
var rings: Lib.Ripples
var plinks: Array
var bubbles: Array
var spikes: Array
var drops: Lib.Drops
var t := 0.0
var done := {}


func create(o_: Dictionary) -> void:
	o = o_
	C = Px.fit(o.palette, 8)
	R = Px.Rng.new(o.seed)
	ST = Lib.rock()
	phi = R.range(0.0, TAU)
	ps = Px.Particles.new({"rng": R})
	mist = Lib.Mist.new()
	lights = Px.Lights.new()
	rings = Lib.Ripples.new({"sy": SY})
	plinks = []
	bubbles = []
	spikes = Px.arr(FINGERS, func(k: int): return {"a": fmod((k * TAU) / FINGERS + phi, TAU), "L": R.range(0.2, 0.36)})
	drops = Lib.Drops.new({
		"sy": SY,
		"g": G,
		"onLand": func(d: Dictionary):
			# every drop that comes down plinks: a white fleck, a ring, and the bigger ones throw up a tiny crown
			rings.add(d.x, d.z, 0.6, 2.0 + d.s * 1.8, 0.34 + d.s * 0.1, {"n": 1.0, "k": 0.95, "hot": 0.06})
			plinks.append({"x": d.x, "y": d.z * SY, "s": d.s, "age": 0.0})
			if d.s > 1 and not d.get("small", false):
				var i := 0
				while i < d.s:
					var a := R.range(0.0, TAU)
					var v := R.range(10.0, 34.0)
					drops.add({"x": d.x, "z": d.z, "h": 0.5, "vx": cos(a) * v, "vz": sin(a) * v, "vh": R.range(55.0, 110.0), "s": 1.0, "small": true, "life": 1.0})
					i += 1,
	})
	t = 0.0
	done = {}


func once(key: String, at: float) -> bool:
	if done.has(key) or not (t >= at):
		return false
	done[key] = true
	return true


# the lip isn't level: it rises and dips round the crown
func scallop(a: float, h: float) -> float:
	return h * (0.86 + 0.14 * Px.noise(cos(a) * 2.2 + sin(a) * 1.3 + phi * 3.0, o.seed))


# the crown: a thin sheet from its foot to a rolled lip. The far wall's shadowed inside shows over the near
# lip; the near wall is see-through between bright streaks, white down its lit edge; fingers rise off the lip
func crown(p: Px.Painter, back: bool) -> void:
	var u := t - HIT
	var h := height(u)
	if u < 0.0 or h < 0.7:
		return
	var r0 := foot(u)
	var rt := lip(u)
	var white := u < 0.045
	var cells := {}
	var put := func(x: float, y: float, c: Variant, a: float, rank: int) -> void:
		var X := floori(x)
		var Y := floori(y)
		var key := (Y + 4096) * 8192 + X + 4096
		var cur: Variant = cells.get(key)
		if cur == null or rank > cur.r:
			cells[key] = {"x": X, "y": Y, "c": c, "a": a, "r": rank}
	var n := ceilf(rt * TAU * 1.6)
	for i in int(n):
		var a := (i / n) * TAU
		var s := sin(a)
		var c := cos(a)
		if (s < 0.0) != back:
			continue
		var lane := floorf(((a + phi) * rt) / 2.2)
		var streak := Px.rand(lane, 31) < 0.3
		var H := scallop(a, h)
		# as it falls, each lane of the sheet gives way from the top at its own moment
		var keep := 1.0 - Px.clamp((u - 0.13 - 0.14 * Px.rand(lane, 7)) / 0.1)
		var steps := ceilf(H * 1.4) + 2.0
		var k := 0
		while k <= steps * keep:
			var v := k / steps
			var r := r0 + (rt - r0) * pow(v, 2.2)
			var x := c * r
			var y := s * r * SY - H * v
			if white:
				put.call(x, y, WHITE, 1.0, 3)
			elif back:
				put.call(x, y, ((C[5] if streak else C[4]) if v > 0.72 else (C[3] if streak else C[2])), 1.0, 1)
			elif absf(c) > 0.9:
				put.call(x, y, ((WHITE if absf(c) > 0.97 else C[6]) if c < 0.0 else C[4]), 1.0, 2)
			elif v < 0.1:
				put.call(x, y, WHITE if v < 0.05 else C[6], 1.0, 2)
			elif streak:
				put.call(x, y, C[6] if c < -0.2 else C[5], 1.0, 1)
			else:
				put.call(x, y, C[5] if c < 0.0 else C[4], 0.22, 0)
			k += 1
		# the rolled lip: a hard white line on the near side, softer on the far, gone where the lane broke
		if not white and keep >= 1.0:
			var x := c * rt
			var y := s * rt * SY - H
			put.call(x, y, C[5] if back else (WHITE if c < 0.45 else C[6]), 1.0, 3)
			if not back and c < 0.2:
				put.call(x, y + 1.0, C[6], 1.0, 2)
	for q: Dictionary in cells.values():
		if q.r == 0:
			p.blend(q.x, q.y, q.c, q.a)
		else:
			p.px(q.x, q.y, q.c)
	# fingers: spikes running on up and out from the lip, a bead on each until it tears off
	var reach := 1.0 - Px.smooth(TEAR, TEAR + 0.1, u)
	for f: Dictionary in spikes:
		if (sin(f.a) < 0.0) != back or reach <= 0.0:
			continue
		var H := scallop(f.a, h)
		var L: float = h * f.L * reach
		var x0: float = cos(f.a) * rt
		var y0: float = sin(f.a) * rt * SY - H
		var x1: float = x0 + cos(f.a) * L * 0.45
		var y1: float = y0 - L
		if L >= 1.0:
			p.line(x0, y0, x1, y1, WHITE if white else (C[4] if back else C[6]))
		if u > 0.04 and u < TEAR:
			Lib.bead(p, x1 - (0.0 if back else 0.5), y1 - 1.0, 0.0, -1.0, 1.0 if back else 2.0, C)
		if not back and sin(f.a) > 0.3:
			p.glow(x0, y0, 6.0, C[5], 0.22 * reach)


func jet(p: Px.Painter) -> void:
	var u := t - HIT - JET
	var h := jetH(u)
	if u < 0.0 or h < 0.8:
		return
	var top := -h
	# a mound of water heaves up under it
	p.ellipse(0.0, 0.0, 5.0, 2.4, func(d: float, a: float): return null if sin(a) > 0.0 else (WHITE if d < 0.5 else (C[6] if cos(a) < 0.0 else C[5])))
	p.shade(-3.0, top - 2.0, 3.0, 0.0, func(x: float, y: float, out):
		var v := Px.clamp((y - top) / h)
		var w := 1.15 + 1.5 * v * v * v
		var q := x / w
		if absf(q) > 1.0:
			return
		out.c = C[6] if q < -0.5 else (WHITE if q < 0.3 else (C[5] if q < 0.72 else C[4])))
	if u < 0.12:
		# the bulb at its tip, about to pinch off
		p.circle(0.0, top - 1.0, 1.7, C[5])
		p.circle(-0.3, top - 1.3, 1.1, C[6])
		p.px(-1.0, top - 2.0, WHITE)
	p.glowLine(0.0, -1.0, 0.0, top, 7.0, C[5], 0.3)


func update(dt: float) -> void:
	t += dt
	if once("hit", HIT):
		lights.add(0.0, -6.0, 52.0, C[5], 0.6, 0.45)
		lights.add(0.0, -4.0, 16.0, WHITE, 0.5, 0.08)
		rings.add(0.0, 0.0, 8.0, 56.0, 2.0, {"n": 2.0, "gap": 3.4, "k": 1.35, "hot": 0.16, "glint": 1.0})
		rings.add(0.0, 0.0, 5.0, 38.0, 1.7, {"n": 1.0, "k": 0.9, "delay": 0.14})
		# the first sheet of spray, thrown up fast and fine
		for i in 20:
			var a := R.range(0.0, TAU)
			var v := R.range(50.0, 125.0)
			drops.add({"x": cos(a) * 3.0, "z": sin(a) * 3.0, "h": R.range(1.0, 6.0), "vx": cos(a) * v, "vz": sin(a) * v, "vh": R.range(160.0, 270.0), "s": 2.0 if R.chance(0.25) else 1.0, "delay": R.range(0.0, 0.04)})
		# mist rolls out low along the water
		for i in 9:
			var s := 1.0 if i % 2 else -1.0
			var x := s * R.range(4.0, 12.0)
			mist.add(x, -R.range(1.0, 7.0), s * R.range(25.0, 70.0), -R.range(4.0, 16.0), R.range(2.5, 4.0), R.range(7.0, 11.0), R.range(0.9, 1.5), C[6] if R.chance(0.5) else C[5], R.range(0.3, 0.42), R.range(0.0, 0.1))
	if once("spray", HIT + 0.04):
		for i in 20:
			var a := R.range(0.0, TAU)
			ps.spawn(P.FLAKE, cos(a) * 9.0, sin(a) * 9.0 * SY - R.range(6.0, 15.0), cos(a) * R.range(25.0, 90.0), -R.range(30.0, 100.0), R.range(0.7, 1.3), WHITE if R.chance(0.5) else C[6], R.range(0.6, 1.5))
		for i in 5:
			ps.spawn(P.STAR, R.range(-13.0, 13.0), -R.range(6.0, 20.0), 0.0, -4.0, R.range(0.25, 0.55), C[6], R.range(1.0, 2.4), R.range(0.0, 0.15))
	if once("tear", HIT + TEAR):
		# the beads on the finger tips tear off and arc away
		var h := height(TEAR)
		var rt := lip(TEAR)
		for f: Dictionary in spikes:
			var a: float = f.a + R.range(-0.08, 0.08)
			var v := R.range(32.0, 88.0)
			var L: float = h * f.L
			drops.add({"x": cos(f.a) * (rt + L * 0.45), "z": sin(f.a) * rt, "h": h + L + 1.0, "vx": cos(a) * v, "vz": sin(a) * v, "vh": R.range(90.0, 190.0), "s": 3.0 if R.chance(0.3) else 2.0})
	# as the crown gives way its lip comes apart into drops
	var u := t - HIT
	if u > 0.13 and u < 0.3 and R.chance(0.3):
		var a := R.range(0.0, TAU)
		var rt := lip(u)
		var v := R.range(15.0, 45.0)
		drops.add({"x": cos(a) * rt, "z": sin(a) * rt, "h": scallop(a, height(u)) * R.range(0.6, 1.0), "vx": cos(a) * v, "vz": sin(a) * v, "vh": R.range(-10.0, 45.0), "s": 2.0 if R.chance(0.3) else 1.0})
	if once("fall", HIT + 0.3):
		# the crown falls back, shedding a few heavy drops close in
		for i in 8:
			var a := R.range(0.0, TAU)
			var r := lip(0.3)
			var v := R.range(15.0, 40.0)
			drops.add({"x": cos(a) * r, "z": sin(a) * r, "h": R.range(3.0, 7.0), "vx": cos(a) * v, "vz": sin(a) * v, "vh": R.range(30.0, 80.0), "s": 2.0 if R.chance(0.4) else 1.0})
	if once("bead", HIT + JET + 0.12):
		# the jet's tip pinches off into a bead that hangs, then drops back
		drops.add({"x": 0.0, "z": 0.2, "h": jetH(0.12) + 1.0, "vx": R.range(-6.0, 6.0), "vz": 0.0, "vh": 55.0, "s": 3.0})
		for i in 3:
			mist.add(R.range(-3.0, 3.0), -jetH(0.12) + R.range(2.0, 8.0), R.range(-14.0, 14.0), -R.range(4.0, 12.0), 2.0, R.range(4.0, 6.0), R.range(0.6, 1.0), C[6], 0.3)
	if once("slump", HIT + JET + 0.38):
		rings.add(0.0, 0.0, 3.0, 30.0, 1.5, {"n": 2.0, "gap": 2.6, "k": 0.9})
		for i in 4:
			mist.add(R.range(-6.0, 6.0), -R.range(1.0, 4.0), R.range(-30.0, 30.0), -R.range(3.0, 10.0), 2.5, R.range(6.0, 9.0), R.range(0.8, 1.2), C[5], 0.28)
	# the stone sinks and lets go of its air: a few bubbles come up and pop
	for ia: Array in [[0, 0.95], [1, 1.2], [2, 1.5]]:
		var i: int = ia[0]
		var at: float = ia[1]
		if once("glug" + str(i), HIT + at):
			bubbles.append({"x": R.range(-5.0, 5.0), "z": R.range(-6.0, 6.0), "t0": t, "r": R.range(1.3, 2.3), "popped": false})
	for b: Dictionary in bubbles:
		if not b.popped and t - b.t0 > 0.2:
			b.popped = true
			rings.add(b.x, b.z, 1.0, 7.0, 0.6, {"n": 1.0, "k": 0.9})
			plinks.append({"x": b.x, "y": b.z * SY, "s": 1.0, "age": 0.0})
			for i in 2:
				drops.add({"x": b.x, "z": b.z, "h": 1.0, "vx": R.range(-20.0, 20.0), "vz": R.range(-10.0, 10.0), "vh": R.range(50.0, 90.0), "s": 1.0, "small": true, "life": 1.0})
	var j := plinks.size() - 1
	while j >= 0:
		plinks[j].age += dt
		if plinks[j].age > 0.14:
			plinks.remove_at(j)
		j -= 1
	drops.update(dt)
	rings.update(dt)
	mist.update(dt)
	ps.update(dt)
	lights.update(dt)


func drawBack(p: Px.Painter) -> void:
	var u := t - HIT
	# the cavity the stone punches, dark inside the foot of the crown
	if u > 0.0 and u < 0.26:
		var r := foot(u) * 0.85 * (1.0 - Px.smooth(0.12, 0.26, u))
		p.ellipse(0.0, 0.0, r, r * SY + 0.6, func(d: float, a: float): return C[1] if sin(a) < 0.0 else C[2])
	rings.draw(p, C, -1.0)
	crown(p, true)
	drops.draw(p, C, "back")


func draw(p: Px.Painter) -> void:
	var u := t - HIT
	rings.draw(p, C, 1.0)
	if u > 0.2:
		var rx := 4.0 + 11.0 * Px.Ease.outCubic(Px.clamp((u - 0.2) / 0.7))
		var k := Px.smooth(0.2, 0.32, u) * (1.0 - Px.smooth(0.5, 2.0, u)) * 0.9
		Lib.lace(p, 0.0, 0.0, rx, rx * SY + 0.5, k, C, t, o.seed)
	crown(p, false)
	jet(p)
	for b: Dictionary in bubbles:
		var g: float = (t - b.t0) / 0.2
		if g > 1.0:
			continue
		var r: float = b.r * Px.Ease.outBack(g)
		var x: float = b.x
		var y: float = b.z * SY
		var a := PI
		while a <= TAU + 0.01:
			p.dot(x + cos(a) * r, y + sin(a) * r, C[6])
			a += 0.5 / maxf(1.0, r)
		p.px(x - r * 0.4, y - r * 0.6, WHITE)
		p.glow(x, y - 1.0, 4.0, C[5], 0.25)
	for q: Dictionary in plinks:
		var k: float = q.age / 0.14
		if k < 0.5:
			p.px(q.x, q.y, WHITE)
		if q.s > 1:
			p.line(q.x, q.y - 1.0, q.x, q.y - 1.0 - 3.0 * (1.0 - k), WHITE if k < 0.4 else C[6])
		p.glow(q.x, q.y, 4.0, C[5], 0.3 * (1.0 - k))
	drops.draw(p, C, "front")
	# the hit: a flat white flash on the surface for two frames
	if u >= 0.0 and u < 0.07:
		p.ellipse(0.0, 0.0, 10.0, 2.4, func(d: float): return WHITE if d < 0.6 else C[6])
		Px.sparkle(p, 0.0, -3.0, 5.0 * (1.0 - u / 0.07), C[6], C[5], 0.5)
	# the stone, falling fast with a streak of air off it
	if o.stone and t < HIT:
		var v := t / HIT
		var y := -70.0 + 70.0 * (0.4 * v + 0.6 * v * v)
		p.line(0.0, y - 12.0, 0.0, y - 3.0, ST[4], func(w: float): return w * 0.8)
		Lib.pebble(p, 0.0, y, 2.6, ST)
	mist.draw(p, C[5])
	ps.draw(p)
	lights.draw(p)
	# the disturbed water keeps a cool light on it while it settles
	if u > 0.0:
		p.glow(0.0, -2.0, 34.0, C[4], 0.2 * (1.0 - Px.smooth(0.0, 1.6, u)))
		p.glow(0.0, 2.0, 64.0, C[3], 0.16 * (1.0 - Px.smooth(0.1, 2.1, u)))
