# The fire (nested flame tongues with leaps and flicker, licks, flame puffs cooling to smoke, wandering embers,
# layered warm light) is adapted from Sprite Fusion's open-source fire
# (https://www.spritefusion.com/pixel-art-vfx/fire), MIT License, Copyright (c) 2026 Hugo Duprez.
# port-of: src/fx/critters/flying-skull.js@0e2ff5f742c831ec1c45ae9e414f14b500771223
extends RefCounted

const Px := preload("../../core/px.gd")
const Lib := preload("_lib.gd")
const P := Px.P
const PF := Px.PF

static var meta := {
	"name": "Flying skull",
	"desc": "A cracked bone skull bobs in the air, jaw chattering, eyes burning, a fire roaring off its crown that sheds flame puffs, embers and smoke and throws warm light.",
	"tags": ["critter", "skull", "undead", "fire", "flying", "monster", "loop"],
	"size": [96, 132],
	"origin": [48, 120],
	"duration": 2.4,
	"loop": true,
	"fps": 30,
	"bg": "ground",
	"options": {
		"palette": ["#4a1712", "#8a1f17", "#c9281f", "#f2561d", "#ff8a2a", "#ffc23d", "#ffe26b", "#fff3a6", "#ffffff"],
		"bone": ["#1a1114", "#3e2b2a", "#6b5144", "#9e8467", "#cdb892", "#efe2bf", "#fffaea"],
		"hover": 40,
		"floor": true,
		"seed": 1,
	},
}

static var D: float = meta.duration
static var GRID := Lib.Grid.new(-14, -20, 28, 40)
static var SOCKET := Px.hex("#120a0c")
static var SWARM := Lib.Swarm.new()


# where the skull is at loop time t: a slow figure-eight bob, and its velocity (for the flames to trail)
static func at(t: float, hover: float) -> Dictionary:
	var a := (t / D) * TAU
	return {
		"x": 3.0 * sin(a),
		"y": -hover + 3.0 * sin(2.0 * a + 0.5),
		"vx": (3.0 * TAU * cos(a)) / D,
		"vy": (6.0 * TAU * cos(2.0 * a + 0.5)) / D,
	}


# the jaw: two bursts of chatter a loop, a wide gape at the end of the second
static func jaw(t: float) -> float:
	var ch := maxf(0.0, sin((t / D) * TAU * 22.0))
	var b1 := burst(t, 0.15, 0.75)
	var b2 := burst(t, 1.3, 1.95)
	var gape := burst(t, 1.95, 2.3)
	return Px.round(maxf(ch * 2.4 * maxf(b1, b2), gape * 3.4))


static func burst(t: float, a: float, b: float) -> float:
	return 0.0 if (t <= a or t >= b) else sin(PI * ((t - a) / (b - a))) ** 0.5


static func flick(t: float) -> float:
	return 0.74 + 0.16 * Lib.lnoise(t, D, 18.0, 0.0, 1) + 0.1 * Lib.lnoise(t, D, 46.0, 0.0, 2)


# the skull's shape, centered on (0, 0): a cranium, cheekbones narrowing to the upper jaw
static func inCranium(x: float, y: float) -> bool:
	return (x / 11.0) ** 2 + ((y + 6.0) / 10.5) ** 2 <= 1.0


static func inFace(x: float, y: float) -> bool:
	return y >= -3.0 and y <= 6.5 and absf(x) <= Px.lerp(10.2, 7.2, (y + 3.0) / 9.5)


static func inSkull(x: float, y: float) -> bool:
	return inCranium(x, y) or inFace(x, y)


static func browY(x: float) -> float:
	return -6.6 + (8.5 - absf(x)) * 0.3


static func inSocket(x: float, y: float) -> bool:
	return ((absf(x) - 5.1) / 3.3) ** 2 + ((y + 2.9) / 3.3) ** 2 <= 1.0 and y > browY(x)


const NOSE := [[-1.0, 1.0], [0.0, 1.0], [-2.0, 2.0], [-1.0, 2.0], [0.0, 2.0], [1.0, 2.0], [-2.0, 3.0], [1.0, 3.0]]
const CRACK := [[4.0, -16.0], [4.0, -15.0], [5.0, -14.0], [5.0, -13.0], [4.0, -12.0], [5.0, -11.0], [6.0, -10.0], [6.0, -9.0]]


static func topY(x: float) -> float:
	return -6.0 - 10.5 * sqrt(maxf(0.0, 1.0 - (x / 11.0) ** 2))


static func skull(g: Lib.Grid, B: Array, F: Array, open: float, t: float) -> void:
	var warm := Px.mix(B[6], F[6], 0.45)
	var rim := Px.mix(B[5], F[5], 0.3)
	var lx := -4.0
	var ly := -15.0
	var lit := func(x: float, y: float, k: float) -> bool: return inSkull(lx + (x - lx) / k, ly + (y - ly) / k)
	g.clear()
	g.shade(-12.0, -17.0, 12.0, 8.0, func(x, y, o):
		if not inSkull(x, y):
			return 0
		var c: int = B[5] if lit.call(x, y, 0.45) else (B[4] if lit.call(x, y, 0.74) else B[3])
		# temples pinch in behind the sockets
		if absf(x) > 8.2 and y > -7.0 and y < -1.0:
			c = B[3] if x < 0.0 else B[2]
		if not inSkull(x + 2.0, y + 2.2) or (x > 0.0 and not inSkull(x + 2.6, y)):
			c = B[2]
		if not inSkull(x + 1.0, y + 1.2) and y > 2.0:
			c = B[1]
		# the crown catches the fire
		if not inSkull(x, y - 1.5):
			c = warm if absf(x) < 7.0 else rim
		elif not inSkull(x, y - 2.5) and absf(x) < 6.0:
			c = rim
		# under the brow, the bone drops into shadow
		if y > browY(x) - 1.2 and y < browY(x) + 0.4 and absf(x) > 1.6 and absf(x) < 8.6:
			c = B[4] if x < 0.0 else B[3]
		# cheekbones
		if absf(x) > 6.2 and absf(x) < 9.2 and y > 0.0 and y < 2.0:
			c = B[5] if x < 0.0 else B[3]
		# the upper teeth
		if y > 6.0:
			if absf(x) > 6.4:
				return 0
			var cx := floori(x)
			var gap := cx == -6 or cx == -3 or cx == 2 or cx == 5
			c = B[1] if gap else (((B[5] if x < 0.0 else B[4])) if y < 7.0 else (B[3] if (cx == -1 or cx == 0) else B[4]))
		return c)
	# sockets: dark hollows with an ember glow catching their lower rim
	g.shade(-9.0, -7.0, 9.0, 1.0, func(x, y):
		if not inSocket(x, y):
			return 0
		if not inSocket(x, y + 1.3):
			return Px.mix(B[2], F[4], 0.55)
		return SOCKET)
	for q in NOSE:
		var x: float = q[0]
		var y: float = q[1]
		g.setc(x, y, B[1] if y == 3.0 else SOCKET)
	g.setc(-1, 3, B[2])
	g.setc(0, 3, B[2])
	for q in CRACK:
		var x: float = q[0]
		var y: float = q[1]
		g.setc(x, y, B[1])
		g.setc(x - 1.0, y, B[5])
	g.setc(7, -7, B[1])
	g.setc(8, -6, B[1])
	# the jaw hangs below: rami up the sides, a row of teeth, the chin
	var jy := 8.0 + open
	g.shade(-8.0, 4.0, 8.0, jy + 6.0, func(x, y):
		var ax := absf(x)
		if ax > 6.6 and ax < 8.1 and y > 4.0 and y < jy + 2.0:
			return B[3] if x < 0.0 else B[2]
		if y < jy or y > jy + 5.5:
			return 0
		var v: float = y - jy
		var hw := 7.4 - v * 0.45 - ((v - 4.0) * 1.2 if v > 4.0 else 0.0)
		if ax > hw:
			return 0
		if v < 1.5:
			if ax > 6.0:
				return B[4] if x < 0.0 else B[3]
			var cx := floori(x)
			var gap := cx == -5 or cx == -2 or cx == 1 or cx == 4
			return B[1] if gap else (B[5] if v < 1.0 else B[4])
		return B[1] if not inJaw(x + 1.6, y + 1.6, jy) else ((B[4] if x < 0.0 else B[3]) if v < 2.5 else B[3]))
	if open > 0.0:
		var y := 8.0
		while y < jy:
			for x in range(-6, 6):
				g.setc(x, y, Px.mix(SOCKET, F[3], 0.5) if y == jy - 1.0 else SOCKET)
			y += 1.0
	g.outline(func(x, y, nx, ny): return Px.mix(B[0], F[1], 0.75) if ny < 0.0 else B[0])


static func inJaw(x: float, y: float, jy: float) -> bool:
	var v := y - jy
	var hw := 7.4 - v * 0.45 - ((v - 4.0) * 1.2 if v > 4.0 else 0.0)
	return v >= 0.0 and v <= 5.5 and absf(x) <= hw


# the tongues of fire on the crown: one every 2 px, tallest in the middle, leaping now and then
static func crown(seed: float) -> Array:
	var out := []
	var x := -10.0
	while x <= 10.0:
		out.append({"x": x, "h": 13.0 + 13.0 * (1.0 - (x / 11.0) ** 2), "w": 2.3 + Px.rand(x + 20.0, seed, 3) * 0.8, "n": 37.0 + x * 3.0 + seed * 11.0, "front": false})
		x += 2.0
	# and up the temples
	for s in [-1.0, 1.0]:
		out.append({"x": s * 11.0, "y": -5.0, "h": 10.0, "w": 1.8, "n": 61.0 + s * 13.0 + seed * 5.0, "front": false})
	x = -5.0
	while x <= 5.0:
		out.append({"x": x, "h": 5.0 + 3.0 * Px.rand(x * 4.0 + 20.0, seed, 5), "w": 1.6, "n": 91.0 + x * 5.0 + seed * 7.0, "front": true})
		x += 2.5
	return out


static func height(f: Dictionary, t: float, k: float) -> float:
	var leap := maxf(0.0, Lib.lnoise(t, D, 6.0, f.n * 3.1, 70) - 0.55) * 1.6
	return (f.h + 0.25 * f.h * Lib.lnoise(t, D, 8.0, f.n * 1.7, 5) + f.h * leap) * (0.9 + 0.1 * k)


static func draw(p: Px.Painter, time: float, o: Dictionary) -> void:
	var t := Lib.shift(time, D, o.seed)
	var F := Px.fit(o.palette, 9)
	var heat := F.duplicate()
	heat.reverse()
	var B := Px.fit(o.bone, 7)
	var S := at(t, o.hover)
	var k := flick(t)
	var lean := Px.clamp(-S.vx / 60.0, -0.8, 0.8)
	var stretch := Px.clamp(S.vy / 90.0, -0.3, 0.45)
	var tongues := Px.sort(crown(o.seed), func(a, b): return absf(b.x) - absf(a.x))
	var X := Px.round(S.x)
	var Y := Px.round(S.y)
	var lick := func(f: Dictionary) -> float: return Lib.lnoise(t, D, 5.0, f.n, 40) * 2.0 + lean * height(f, t, k) * 0.9 - Px.clamp(f.x * 0.25, -2.0, 2.0)
	# the fire behind: tall tongues off the back of the crown
	for li in 4:
		for f: Dictionary in tongues:
			if not f.front:
				var fy: Variant = f.get("y")
				Lib.tongue(p, X + f.x, Y + (fy if fy != null else topY(f.x) + 3.0), height(f, t, k) * (1.0 + stretch), f.w * (1.0 - 0.25 * absf(lean)), lick.call(f), t, D, f.n, heat, li)
	# embers and flame puffs behind it
	particles(p, t, o, heat, F, true)
	var g := GRID
	skull(g, B, F, jaw(t), t)
	g.draw(p, 1.0, X, Y)
	# the burning eyes
	for s in [-1.0, 1.0]:
		var ex: float = X + s * 5.1 - 0.5
		var ey := Y - 2.4
		var fl := 0.75 + 0.25 * Lib.lnoise(t, D, 30.0, s * 9.0, 12)
		p.px(ex, ey, heat[0])
		p.px(ex + 1.0, ey, heat[1])
		p.px(ex, ey + 1.0, heat[2])
		p.px(ex + 1.0, ey + 1.0, heat[3])
		if fl > 0.8:
			p.px(ex, ey - 1.0, heat[3])
			p.px(ex + 1.0, ey - 1.0, heat[5])
		p.glow(ex + 1.0, ey + 1.0, 6.0, F[5], 0.45 * fl)
		p.glow(ex + 1.0, ey + 0.5, 3.0, F[7], 0.5 * fl)
	# fire in the mouth when it gapes, and a gout of flame breathed out
	var open := jaw(t)
	if open > 0.0:
		p.glow(X, Y + 8.0 + open * 0.5, 4.0 + open * 2.0, F[5], 0.25 * open)
	for i in 9:
		var r := Px.rng(o.seed, i, 21)
		var born := 1.98 + i * 0.03
		var age := Px.wrap(t - born, D)
		var L := r.range(0.25, 0.45)
		if age >= L:
			continue
		var S0 := at(born, o.hover)
		var xy := Px.fly(S0.x + r.range(-3.0, 3.0), S0.y + 11.0, r.range(-22.0, 22.0), r.range(40.0, 75.0), age, -70.0, 3.5)
		Lib.firePuff(p, xy[0], xy[1], 1.0 - age / L, r.range(1.1, 2.0), r.next() * 100.0, heat)
	# the front flames, over the crown
	for li in 4:
		for f: Dictionary in tongues:
			if f.front:
				Lib.tongue(p, X + f.x, Y + topY(f.x) + 1.5, height(f, t, k) * (1.0 + stretch), f.w, lick.call(f) * 0.6, t, D, f.n, heat, li)
	particles(p, t, o, heat, F, false)
	# light: a big warm pool, a hot core over the crown, the eyes
	var br := 0.92 + 0.08 * sin((t / D) * TAU * 2.0)
	p.glow(X + lean * 4.0, Y - 20.0, 74.0 * br * (0.9 + 0.1 * k), Px.mix(F[4], F[5], 0.5), 0.48 * k)
	p.glow(X, Y - 21.0, 24.0, F[6], 0.3 * k)
	p.glow(X, Y - 15.0, 9.0, F[8], 0.16 * k)


# flame puffs off the tongue tips that cool into smoke, licks of flame breaking away, embers wandering up
static func particles(p: Px.Painter, t: float, o: Dictionary, heat: Array, F: Array, back: bool) -> void:
	var sw: Lib.Swarm = SWARM.begin(t)
	sw.ps.sparks = [F[7], F[6], F[4], F[2]]
	if back:
		# smoke from the tips, born where the skull was
		Px.cycle(t, D, 15, o.seed * 7 + 1, func(r): return r.range(1.7, 2.5), func(age, L, r):
			var S0 := at(Px.wrap(t - age, D), o.hover)
			var x0: float = S0.x + r.range(-6.0, 6.0)
			var y0: float = S0.y - 22.0 - r.range(0.0, 8.0)
			var xy := Px.fly(x0, y0, r.range(-5.0, 5.0), -r.range(16.0, 26.0), age, -12.0, 1.2)
			sw.add(P.SMOKE, xy[0] + sin(age * 1.3 + r.next() * 6.0) * 3.0 * age, xy[1], 0.0, 0.0, age, L, Px.mix(Px.hex("#5b5566"), F[2], 0.3), r.range(2.8, 4.4), PF.BIG))
		sw.draw(p)
		return
	# flame puffs: bright, fast, cooling down the ramp as they rise
	Px.cycle(t, D, 40, o.seed * 7 + 2, func(r): return r.range(0.18, 0.36), func(age, L, r):
		var S0 := at(Px.wrap(t - age, D), o.hover)
		var side: bool = r.chance(0.3)
		var a: float = r.sign() * r.range(0.9, 1.45) if side else r.range(-0.8, 0.8)
		var x0: float = S0.x + sin(a) * 10.5
		var y0: float = S0.y - 6.0 - cos(a) * 10.0 - (0.0 if side else r.range(2.0, 10.0))
		var xy := Px.fly(x0, y0, r.range(-6.0, 6.0) + sin(a) * 6.0, -r.range(18.0, 34.0), age, -95.0, 3.2)
		Lib.firePuff(p, xy[0] + sin(age * 17.0 + r.next() * 6.0) * 0.8, xy[1], 1.0 - age / L, r.range(1.0, 2.2), r.next() * 100.0, heat))
	# licks: little blobs of flame breaking off the tips
	Px.cycle(t, D, 18, o.seed * 7 + 3, 0.26, func(age, L, r):
		var S0 := at(Px.wrap(t - age, D), o.hover)
		var fx: float = r.range(-10.0, 10.0)
		var x0: float = S0.x + fx
		var y0: float = S0.y + topY(fx) - r.range(4.0, 16.0) * (1.0 - absf(fx) / 14.0)
		var kk: float = 1.0 - age / L
		var x: float = x0 + r.range(-3.0, 3.0) * age
		var y: float = y0 - r.range(12.0, 20.0) * age
		var rr: float = r.range(0.9, 1.7) * (0.4 + 0.6 * kk)
		p.circle(x, y, rr + 0.6, heat[5] if kk > 0.5 else heat[6])
		if kk > 0.35:
			p.circle(x, y - 0.3, rr * 0.6, heat[2] if kk > 0.7 else heat[4]))
	# embers wander up and cool
	Px.cycle(t, D, 24, o.seed * 7 + 4, func(r): return r.range(1.0, 2.4), func(age, L, r):
		var S0 := at(Px.wrap(t - age, D), o.hover)
		var x0: float = S0.x + r.range(-11.0, 11.0)
		var y0: float = S0.y - r.range(6.0, 24.0)
		var s: float = r.next() * 100.0
		var xy := Px.fly(x0, y0, r.range(-22.0, 22.0), -r.range(25.0, 70.0), age, -20.0, 1.6)
		sw.add(P.EMBER, xy[0] + sin(age * 2.3 + s) * 4.0 * minf(1.0, age), xy[1], 0.0, 0.0, age, L, F[4], 2.0 if r.chance(0.3) else 1.0, 0, s))
	# sparks pop out of the fire now and then, fall, and skip along the floor
	if o.floor:
		Px.cycle(t, D, 5, o.seed * 7 + 5, func(r): return r.range(0.9, 1.4), func(age, L, r):
			var S0 := at(Px.wrap(t - age, D), o.hover)
			var b := Lib.bounce(S0.x + r.range(-6.0, 6.0), S0.y - r.range(10.0, 18.0), r.range(-28.0, 28.0), -r.range(50.0, 110.0), age, 430.0, -0.5, 0.42)
			sw.add(P.SPARK, b.x, b.y, 0.1 if b.rest else b.vx, 0.0 if b.rest else b.vy, age, L, 0, 1.0, 0, r.next() * 100.0))
	sw.draw(p)


static func drawBack(p: Px.Painter, time: float, o: Dictionary) -> void:
	if not o.floor:
		return
	var t := Lib.shift(time, D, o.seed)
	var F := Px.fit(o.palette, 9)
	var S := at(t, o.hover)
	var k := flick(t)
	# its shadow on the floor, and the floor lit warm around it
	Lib.shadow(p, S.x, 0.0, 9.0, 1.6, Px.hex("#0d0a12"), 0.6)
	for x in range(-30, 31, 6):
		p.glow(S.x + x, -1.0, 20.0, Px.mix(F[4], F[5], 0.5), 0.15 * k * (1.0 - absf(x) / 40.0))
