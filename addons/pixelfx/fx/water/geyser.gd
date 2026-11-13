# The column (a banded white core, strands running through it, light down its length) and the slam with its
# floor ring follow Sprite Fusion's open-source holy-light (https://www.spritefusion.com/pixel-art-vfx/holy-light),
# MIT License, Copyright (c) 2026 Hugo Duprez.
# port-of: src/fx/water/geyser.js@2840d89db09c6745a055d6dcc9238617dcc27953
extends "../../core/effect.gd"

const Px := preload("../../core/px.gd")
const Lib := preload("_lib.gd")
const P := Px.P
const WHITE := Px.WHITE

static var meta := {
	"name": "Geyser",
	"desc": "A pool heaves and burbles faster and faster, then blasts a white column of water skyward with a churning foam head; it rains back down in drops and steam, slumps and sputters out.",
	"tags": ["water", "geyser", "eruption", "steam", "column", "nature", "one-shot"],
	"size": [184, 168],
	"origin": [92, 146],
	"duration": 5,
	"loop": false,
	"fps": 30,
	"bg": "ground",
	"options": {"palette": Lib.WATER, "height": 100, "seed": 4},
}

const SY := 0.22
const G := 820.0
const ERUPT := 1.15
const FALL := 2.6
const GONE := 3.3
# small spurts while it builds, and the sputters after: [time, height]
const SPURTS := [[0.46, 7.0], [0.72, 12.0], [0.92, 9.0], [1.04, 15.0], [GONE + 0.15, 15.0], [GONE + 0.55, 8.0]]


static func poolR(tt: float) -> float:
	return (12.0 + 7.0 * Px.smooth(0.0, 1.0, tt) + 15.0 * Px.Ease.outCubic(Px.clamp((tt - ERUPT) / 1.2))) * (1.0 - 0.25 * Px.smooth(GONE, 4.6, tt))


static func poolK(tt: float) -> float:
	return Px.smooth(0.0, 0.2, tt) * (1.0 - Px.smooth(4.0, 4.85, tt))


static func head(tt: float) -> float:
	return Px.smooth(ERUPT + 0.08, ERUPT + 0.3, tt) * (1.0 - Px.smooth(FALL + 0.1, FALL + 0.45, tt))


static func spurt(tt: float) -> float:
	var h := 0.0
	for sh: Array in SPURTS:
		var s0: float = sh[0]
		var hs: float = sh[1]
		h = maxf(h, hs * sin(PI * Px.clamp((tt - s0) / 0.2)))
	return h


var C: Array
var R: Px.Rng
var HMAX: float
var S: float
var ps: Px.Particles
var mist: Lib.Mist
var lights: Px.Lights
var rings: Lib.Ripples
var plinks: Array
var pops: Array
var V0: float
var t := 0.0
var drops: Lib.Drops
var done := {}


func create(o: Dictionary) -> void:
	C = Px.fit(o.palette, 8)
	R = Px.Rng.new(o.seed)
	HMAX = o.height
	S = o.seed
	ps = Px.Particles.new({"rng": R})
	mist = Lib.Mist.new()
	lights = Px.Lights.new()
	rings = Lib.Ripples.new({"sy": SY})
	plinks = []
	pops = []
	V0 = sqrt(2.0 * G * HMAX)
	t = 0.0
	drops = Lib.Drops.new({
		"sy": SY,
		"g": G,
		"onLand": func(d: Dictionary):
			var inPool := Px.hypot(d.x, d.z) < poolR(t)
			rings.add(d.x, d.z, 0.6, (2.5 if inPool else 1.5) + d.s * 1.6, 0.32 + d.s * 0.1, {"n": 1.0, "k": 0.95 if inPool else 0.7, "hot": 0.05})
			plinks.append({"x": d.x, "y": d.z * SY, "s": d.s, "age": 0.0})
			if d.s > 1 and not d.get("small", false):
				for i in 2:
					var a := R.range(0.0, TAU)
					var v := R.range(8.0, 28.0)
					drops.add({"x": d.x, "z": d.z, "h": 0.5, "vx": cos(a) * v, "vz": sin(a) * v, "vh": R.range(45.0, 95.0), "s": 1.0, "small": true, "life": 1.0}),
	})
	done = {}


# how tall the column stands: a fast blast, surging while it holds, slumping when the pressure goes
func top(tt: float) -> float:
	if tt < ERUPT or tt > GONE:
		return 0.0
	return HMAX * Px.Ease.outCubic(Px.clamp((tt - ERUPT) / 0.3)) * (0.93 + 0.07 * Px.noise(tt * 2.2, S)) * (1.0 - Px.Ease.inQuad(Px.clamp((tt - FALL) / (GONE - FALL))))


func once(key: String, at: float) -> bool:
	if done.has(key) or not (t >= at):
		return false
	done[key] = true
	return true


func emit(rate: float, dt: float) -> bool:
	return R.chance(minf(1.0, rate * dt))


# the column: a white core banded out to blue edges, shadowed on the right; 1 px strands whose streaks run up
# in jet time (fast and long low down, bunching where the water slows near the top); it spreads as it rises,
# its sides ragged and running, a sway through it, light all the way up
func column(p: Px.Painter, H: float, thin: float) -> void:
	if H < 1.0:
		return
	var tau := func(h: float) -> float: return (V0 - sqrt(maxf(0.0, V0 * V0 - 2.0 * G * minf(h, HMAX * 0.96)))) / G
	p.shade(-22.0, -H - 2.0, 22.0, 0.0, func(x: float, y: float, out):
		var h := -y
		var v := h / H
		var sway := Px.noise(t * 1.6 + h * 0.025, S + 5.0) * 2.5 * v
		var rag := Px.noise2(h * 0.2 - t * 11.0, 3.0 if x < sway else 7.0, S + 6.0) * (0.5 + 1.8 * v)
		var w := (3.6 + 7.5 * pow(v, 1.8)) * thin + rag
		var q := (x - sway) / maxf(1.0, w)
		var aq := absf(q)
		if aq > 1.0:
			return
		var X := floorf(x)
		var streak := Px.noise2(X * 1.618 + 0.3, (tau.call(h) - t) * 14.0, S)
		var body := Px.noise2(floorf((x + 40.0) / 2.0) * 2.3, (tau.call(h) - t) * 5.0, S + 1.0)
		var lvl := 0 if aq < 0.42 else (1 if aq < 0.7 else (2 if aq < 0.9 else 3))
		if q > 0.38:
			lvl += 1
		if streak > 0.28:
			lvl -= 1
		if body < -0.4:
			lvl += 1
		out.c = [WHITE, C[6], C[5], C[4], C[3]][clampi(lvl, 0, 4)])
	p.glowLine(0.0, 0.0, 0.0, -H, 16.0 + 8.0 * thin, C[5], 0.12 * thin)


# the head: water boiling over at the top and falling back round the column in an umbrella of streaks, foam
# billows churning in it, shadowed underneath, lit on top
func foamHead(p: Px.Painter, H: float, k: float, back: bool) -> void:
	if k <= 0.01 or H < 4.0:
		return
	if back:
		# the umbrella: streaks pouring off the rim of the head, running down and thinning out
		for i in 16:
			var side := 1.0 if i % 2 else -1.0
			var x0 := side * (5.0 + 9.0 * Px.rand(i, S + 20.0)) * k
			var len := (14.0 + 26.0 * Px.rand(i, S + 21.0)) * k
			var speed := 70.0 + 50.0 * Px.rand(i, S + 22.0)
			for j in 3:
				var f := fmod(t * speed / len + j / 3.0 + Px.rand(i, S + 23.0), 1.0)
				var y0 := -H + 2.0 + f * len
				var x := x0 + side * f * f * 6.0
				var L := 1.0 + 4.0 * f * (1.0 - f) * 2.0
				if f < 0.85:
					p.line(x, y0, x + side * 0.6, y0 + L, C[6] if f < 0.4 else (C[5] if f < 0.7 else C[4]))
	for i in 12:
		var a := (i / 12.0) * TAU + t * (1.3 if i % 2 else -1.1)
		var z := sin(a)
		if (z < 0.0) != back:
			continue
		var rho := (3.0 + 7.0 * Px.rand(i, S)) * k
		var x := cos(a) * rho * 1.25 + Px.noise(t * 3.0 + i, S + 8.0) * 2.5
		var y := -H + z * rho * 0.45 + (rho / 10.0) * 4.0 - 4.0 * (1.0 - rho / (10.0 * k)) + Px.noise(t * 3.0 + i + 50.0, S + 9.0) * 2.5
		var r := (2.0 + 2.6 * Px.rand(i, S + 2.0) + 0.7 * sin(t * 7.0 + i)) * k
		if back:
			Lib.billow(p, x, y, r, [C[0], C[1], C[2], C[3], C[3], C[4], C[5], C[5]])
		else:
			p.circle(x + r * 0.15, y + r * 0.25, r, C[4])
			p.circle(x, y, r * 0.82, C[5] if rho > 6.0 * k else C[6])
			p.circle(x - r * 0.25, y - r * 0.3, r * 0.5, WHITE)
	if not back:
		p.glow(0.0, -H - 2.0, 38.0, C[5], 0.34 * k)


func update(dt: float) -> void:
	t += dt
	var H := top(t)
	var hk := head(t)
	var k := t / ERUPT
	# building: bubbles burst on the heaving mound, faster and faster, steam starts to lift
	if t < ERUPT and emit(1.5 + 9.0 * k * k, dt):
		var a := R.range(0.0, TAU)
		var r := R.range(0.0, 7.0)
		var x := cos(a) * r
		var z := sin(a) * r
		pops.append({"x": x, "y": z * SY - R.range(1.0, 3.0), "age": 0.0, "r": R.range(1.0, 2.0)})
		rings.add(x, z, 1.0, R.range(5.0, 9.0), 0.55, {"n": 1.0, "k": 0.85})
		var i := 0
		while i < R.int_(1, 3):
			drops.add({"x": x, "z": z, "h": 2.0, "vx": R.range(-25.0, 25.0), "vz": R.range(-15.0, 15.0), "vh": R.range(50.0, 120.0), "s": 1.0, "small": true, "life": 1.0})
			i += 1
	if t < ERUPT and emit(3.0 + 7.0 * k, dt):
		mist.add(R.range(-8.0, 8.0), -R.range(1.0, 5.0), R.range(-10.0, 10.0), -R.range(6.0, 18.0), 2.0, R.range(5.0, 9.0), R.range(0.9, 1.5), C[6], 0.22)
	for sh: Array in SPURTS:
		var s0: float = sh[0]
		var hs: float = sh[1]
		if once("spurt" + str(s0), s0 + 0.08):
			for i in 3 + Px.roundi(hs / 4.0):
				var a := R.range(0.0, TAU)
				var v := R.range(10.0, 40.0)
				drops.add({"x": 0.0, "z": 0.0, "h": hs * 0.8, "vx": cos(a) * v, "vz": sin(a) * v, "vh": R.range(20.0, 90.0), "s": 2.0 if R.chance(0.3) else 1.0})
	if once("erupt", ERUPT):
		# the blast: light, a ring thrown across the ground, water flung high, steam rolling out
		lights.add(0.0, -26.0, 64.0, C[5], 0.85, 0.6)
		lights.add(0.0, -4.0, 28.0, WHITE, 0.75, 0.1)
		rings.add(0.0, 0.0, 6.0, 40.0, 1.2, {"n": 2.0, "gap": 3.0, "k": 1.2, "hot": 0.12, "glint": 1.0})
		for i in 44:
			var a := R.range(0.0, TAU)
			var v := R.range(30.0, 120.0)
			drops.add({"x": cos(a) * 3.0, "z": sin(a) * 3.0, "h": R.range(2.0, 10.0), "vx": cos(a) * v, "vz": sin(a) * v, "vh": R.range(180.0, 400.0), "s": 3.0 if R.chance(0.15) else (2.0 if R.chance(0.35) else 1.0), "delay": R.range(0.0, 0.12)})
		for i in 12:
			var s := 1.0 if i % 2 else -1.0
			mist.add(s * R.range(3.0, 9.0), -R.range(1.0, 6.0), s * R.range(30.0, 80.0), -R.range(4.0, 18.0), 3.0, R.range(9.0, 14.0), R.range(1.2, 1.9), C[6] if R.chance(0.5) else WHITE, 0.3, R.range(0.0, 0.15))
		for i in 14:
			ps.spawn(P.STAR, R.range(-16.0, 16.0), -R.range(8.0, 80.0), R.range(-10.0, 10.0), -6.0, R.range(0.3, 0.7), WHITE if R.chance(0.5) else C[6], R.range(1.0, 2.6), R.range(0.05, 0.5))
	# holding: the head sheds drops that rain back down, spray hangs off the column, steam pours off the top
	if hk > 0.0:
		if emit(60.0 * hk, dt):
			var a := R.range(0.0, TAU)
			var v := R.range(10.0, 60.0)
			drops.add({"x": R.range(-9.0, 9.0), "z": R.range(-4.0, 4.0), "h": H + R.range(-8.0, 3.0), "vx": cos(a) * v, "vz": sin(a) * v, "vh": R.range(-40.0, 60.0), "s": 3.0 if R.chance(0.08) else (2.0 if R.chance(0.3) else 1.0)})
		if emit(9.0 * hk, dt):
			mist.add(R.range(-8.0, 8.0), -H + R.range(-6.0, 2.0), R.range(-34.0, 34.0), -R.range(14.0, 34.0), 3.0, R.range(8.0, 13.0), R.range(0.9, 1.4), C[6] if R.chance(0.6) else WHITE, 0.2)
		if emit(5.0 * hk, dt):
			mist.add(R.sign() * R.range(3.0, 9.0), -R.range(1.0, 6.0), R.sign() * R.range(20.0, 50.0), -R.range(2.0, 10.0), 3.0, R.range(8.0, 12.0), R.range(1.0, 1.6), C[6], 0.22)
		if emit(40.0 * hk, dt):
			var s := R.sign()
			var hh := R.range(8.0, H * 0.95)
			ps.spawn(P.FLAKE, s * (3.0 + 6.0 * pow(hh / H, 1.8)), -hh, s * R.range(10.0, 45.0), R.range(-20.0, 10.0), R.range(0.6, 1.2), WHITE if R.chance(0.5) else C[6], R.range(0.6, 1.3))
		if emit(4.0 * hk, dt):
			rings.add(R.range(-2.0, 2.0), R.range(-2.0, 2.0), 4.0, poolR(t) * R.range(0.7, 1.0), 0.9, {"n": 1.0, "k": 0.8})
		if emit(7.0 * hk, dt):
			ps.spawn(P.STAR, R.range(-14.0, 14.0), -R.range(10.0, H + 8.0), R.range(-6.0, 6.0), -4.0, R.range(0.25, 0.55), WHITE if R.chance(0.4) else C[6], R.range(0.8, 2.2), 0.0)
	if once("collapse", FALL + 0.12):
		# the head falls apart: a heavy rain of drops all at once
		for i in 40:
			var a := R.range(0.0, TAU)
			var v := R.range(15.0, 80.0)
			drops.add({"x": R.range(-6.0, 6.0), "z": R.range(-3.0, 3.0), "h": top(t) + R.range(-8.0, 4.0), "vx": cos(a) * v, "vz": sin(a) * v, "vh": R.range(-40.0, 60.0), "s": 3.0 if R.chance(0.12) else (2.0 if R.chance(0.35) else 1.0), "delay": R.range(0.0, 0.25)})
		for i in 6:
			mist.add(R.range(-8.0, 8.0), -top(t) + R.range(-6.0, 6.0), R.range(-34.0, 34.0), -R.range(10.0, 26.0), 4.0, R.range(9.0, 13.0), R.range(0.8, 1.2), C[6], 0.18)
	var j := pops.size() - 1
	while j >= 0:
		pops[j].age += dt
		if pops[j].age > 0.12:
			pops.remove_at(j)
		j -= 1
	j = plinks.size() - 1
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
	# the pool: dark see-through water, a lit far rim
	var pr := poolR(t)
	var pk := poolK(t)
	if pk > 0.0:
		p.each(-pr, -pr * SY, pr, pr * SY, func(x: float, y: float, sx: int, sy: int):
			var d := pow(x / pr, 2.0) + pow(y / (pr * SY), 2.0)
			if d > 1.0:
				return
			p.blendPx(sx, sy, C[2] if d < 0.15 else C[1], 0.6 * pk * minf(1.0, (1.0 - d) * 4.0))
			if y < 0.0 and d > 0.78 and d < 0.95:
				p.blendPx(sx, sy, C[4], 0.7 * pk))
	rings.draw(p, C, -1.0)
	var u := (t - ERUPT) / 0.4
	if u > 0.0 and u < 1.0:
		Lib.ring(p, 0.0, 0.5, 6.0 + 42.0 * Px.Ease.outCubic(u), SY, 1.5 * (1.0 - u), C, {"n": 3.0, "gap": 1.6 + 2.0 * u, "half": -1.0, "hot": u < 0.3, "seed": 9.0})
	foamHead(p, top(t), head(t), true)
	drops.draw(p, C, "back")


func draw(p: Px.Painter) -> void:
	var H := top(t)
	var hk := head(t)
	var k := Px.clamp(t / ERUPT)
	var thin := Px.smooth(ERUPT, ERUPT + 0.12, t) * (1.0 - 0.55 * Px.smooth(FALL, GONE, t))
	rings.draw(p, C, 1.0)
	var u := (t - ERUPT) / 0.4
	if u > 0.0 and u < 1.0:
		Lib.ring(p, 0.0, 0.5, 6.0 + 42.0 * Px.Ease.outCubic(u), SY, 1.5 * (1.0 - u), C, {"n": 3.0, "gap": 1.6 + 2.0 * u, "half": 1.0, "hot": u < 0.3, "seed": 9.0})
	# foam rides the pool round the foot of the column
	var fk := Px.smooth(ERUPT, ERUPT + 0.3, t) * (1.0 - Px.smooth(GONE - 0.3, 4.4, t))
	if fk > 0.0:
		Lib.lace(p, 0.0, 0.0, 8.0 + 10.0 * fk, (8.0 + 10.0 * fk) * SY + 0.5, fk, C, t, S)
	# the heaving mound while it builds, beating faster
	if t < ERUPT + 0.05:
		var beat := pow(maxf(0.0, sin(t * (8.0 + 18.0 * k * k))), 3.0)
		var rd := 4.0 + 3.5 * k + 1.5 * beat
		var hd := 1.5 + 3.0 * k + 3.0 * beat
		p.shade(-rd - 1.0, -hd - 1.0, rd + 1.0, 0.5, func(x: float, y: float, out):
			var dx := x / rd
			var dy := y / hd
			var d := dx * dx + dy * dy
			if d > 1.0 or y > 0.5:
				return
			# water heaving up: a white rim where it faces the light, a tinted body, shadow low on the right
			var lit := -dx * 0.7 - dy * 0.7
			var rim := d > 0.68
			out.c = (WHITE if lit > 0.3 else (C[6] if lit > -0.15 else C[4])) if rim else (C[6] if lit > 0.55 else (C[5] if lit > 0.12 else (C[4] if lit > -0.3 else C[3]))))
		p.px(-rd * 0.35, -hd * 0.6, WHITE)
		p.glow(0.0, -5.0, 16.0 + 16.0 * k + 8.0 * beat, C[5], 0.06 + 0.12 * k + 0.12 * beat)
	# spurts while it builds and sputters as it dies: a short white jet with a bead on top
	var sp := spurt(t)
	if sp > 1.0 and H < 1.0:
		p.shade(-2.0, -sp - 1.0, 2.0, 0.0, func(x: float, y: float, out):
			var q := x / (1.0 + 0.8 * (1.0 + y / sp))
			if absf(q) > 1.0:
				return
			out.c = C[6] if q < -0.3 else (WHITE if q < 0.35 else C[5]))
		p.circle(0.0, -sp, 1.3, C[6])
		p.px(0.0, -sp - 1.0, WHITE)
		p.glowLine(0.0, 0.0, 0.0, -sp, 8.0, C[5], 0.3)
	column(p, H, thin)
	# the foot: billows boil out round it
	if hk > 0.0 or (H > 1.0 and t < GONE):
		for i in 7:
			var a := (i / 7.0) * TAU + t * 2.1
			var r := 4.0 + 2.0 * sin(t * 5.0 + i * 1.7)
			var x := cos(a) * r * 1.3
			var y := sin(a) * r * SY - 2.0
			Lib.billow(p, x, y, (1.6 + 1.2 * Px.rand(i, S + 4.0)) * maxf(hk, thin * 0.6), C)
	foamHead(p, H, hk, false)
	for q: Dictionary in pops:
		var g: float = q.age / 0.12
		for dd: Array in [[1.0, 0.0], [-1.0, 0.0], [0.7, -0.7], [-0.7, -0.7], [0.0, -1.0]]:
			var dx: float = dd[0]
			var dy: float = dd[1]
			p.dot(q.x + dx * (q.r + 3.0 * g), q.y + dy * (q.r + 3.0 * g), C[6], 1.0 - g)
	for q: Dictionary in plinks:
		var g: float = q.age / 0.14
		if g < 0.5:
			p.px(q.x, q.y, WHITE)
		if q.s > 1:
			p.line(q.x, q.y - 1.0, q.x, q.y - 1.0 - 3.0 * (1.0 - g), WHITE if g < 0.4 else C[6])
		p.glow(q.x, q.y, 4.0, C[5], 0.25 * (1.0 - g))
	drops.draw(p, C, "front")
	# the blast's first two frames: a white burst at the vent
	var f := (t - ERUPT) / 0.07
	if f >= 0.0 and f < 1.0:
		p.circle(0.0, -4.0, 7.0 * (1.0 - f * 0.4), WHITE)
		p.ellipse(0.0, 0.0, 12.0, 2.6, func(d: float): return WHITE if d < 0.6 else C[6])
	ps.draw(p)
	mist.draw(p, C[5])
	lights.draw(p)
	# light: the column and its head, the pool round its foot
	if H > 1.0:
		p.glowLine(0.0, 0.0, 0.0, -H, 26.0, C[4], 0.2 * thin)
	p.glow(0.0, -2.0, 46.0, C[4], 0.24 * maxf(hk, 0.3 * k * (1.0 if t < ERUPT else 0.0)))
	p.glow(0.0, 2.0, 60.0, C[3], 0.12 * poolK(t))
