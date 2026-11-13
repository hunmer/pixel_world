# The crack-and-burst recipe (cracks walking out from the point of impact, a white frame, the ice flung apart
# as shards with ice dust and glints) is adapted from Sprite Fusion's open-source ice
# (https://www.spritefusion.com/pixel-art-vfx/ice), MIT License, Copyright (c) 2026 Hugo Duprez.
# port-of: src/fx/ice/ice-shatter.js@0167dbb72c3374ef1826c6d5fffeb3bd96628822
extends "../../core/effect.gd"

const Px := preload("../../core/px.gd")
const Lib := preload("_lib.gd")
const P := Px.P
const B := Px.B
const WHITE := Px.WHITE

static var meta := {
	"name": "Ice shatter",
	"desc": "A block of ice takes a hit from the left: it jolts, cracks race over its faces, it flashes white and bursts into chunks that tumble, bounce and skid off in a roll of ice dust.",
	"tags": ["ice", "shatter", "break", "destroy", "impact", "directional", "one-shot"],
	"size": [224, 112],
	"origin": [68, 90],
	"duration": 2.8,
	"loop": false,
	"fps": 30,
	"bg": "ground",
	"options": {"palette": ["#151a3d", "#212f6b", "#2c58aa", "#3a8bd8", "#62c8f4", "#a6ecff", "#dcfbff", "#ffffff"], "seed": 6},
}

const HIT := 0.26
const CRACK2 := 0.4
const SHIVER := 0.54
const FLASH := 0.62
const BURST := 0.68
# the block, seen from the front and a little above: a front face, a top, a side in shadow
const FRONT := [[-16, 0], [-16, -28], [12, -28], [12, 0]]
const TOP := [[-16, -28], [-8, -34], [20, -34], [12, -28]]
const SIDE := [[12, 0], [12, -28], [20, -34], [20, -6]]
const SIL := [[-16, 0], [-16, -28], [-8, -34], [20, -34], [20, -6], [12, 0]]
const HIT_AT := [-16, -15]
const PLANE := [[-16, -21], [-5, -28], [3, -13], [-16, -9]]  # a fracture plane inside, lighter
const SHADE := [[5, -28], [12, -28], [12, -10]]  # the far corner in shadow

var C: Array
var R: Px.Rng
var ps: Px.Particles
var bits: Px.Bits
var lights: Px.Lights
var scuffs: Array = []
var panes: Lib.Panes
# the ice's insides: veins of frost and trapped bubbles in the front face
var veins: Array = []
var bubbles: Array = []
var cracks: Array
var cracks2: Array
var t := 0.0
var struck := false
var burst := false
var wave2 := false
var white := false


func splinter(x: float, y: float, vx: float, n: int) -> void:
	for i in n:
		bits.add({"kind": B.SHARD, "x": x + R.range(-2.0, 2.0), "y": y - 1.0, "vx": vx * 0.6 + R.range(-35.0, 45.0), "vy": -R.range(30.0, 100.0), "g": 0.8, "drag": 0.6, "bounce": 0.35, "life": R.range(0.4, 0.8), "a": R.range(0.0, TAU), "va": R.range(-18.0, 18.0), "s": R.range(1.2, 2.4), "c": C[R.int_(4, 7)]})


func inside(x: float, y: float) -> bool:
	return Lib.inPoly(SIL, x, y)


func create(o: Dictionary) -> void:
	C = Px.fit(o.palette, 8)
	R = Px.Rng.new(o.seed)
	var floor_ := func(): return 0.0
	ps = Px.Particles.new({"rng": R, "ground": floor_, "sparks": [C[7], C[6], C[5], C[4]], "haze": C[5]})
	bits = Px.Bits.new({"ground": floor_})
	lights = Px.Lights.new()
	scuffs = []
	panes = Lib.Panes.new({
		"ground": floor_,
		"onLand": func(q: Dictionary, x: float, y: float, v: float) -> void:
			# a chunk hitting the floor: a puff of ice dust, a few splinters, sometimes a glint
			if v < 100.0:
				return
			ps.spawn(P.VAPOUR, x, y - 1.0, q.vx * 0.3 + R.range(-15.0, 15.0), -R.range(2.0, 10.0), R.range(0.4, 0.7), C[6], R.range(1.6, 2.8))
			splinter(x, y, q.vx, 2)
			if R.chance(0.3):
				ps.spawn(P.STAR, x, y - 3.0, 0.0, -5.0, R.range(0.2, 0.4), WHITE, R.range(0.8, 1.6)),
		"onSkid": func(_q: Dictionary, x: float) -> void:
			# sliding chunks scuff frost onto the floor
			if R.chance(0.5):
				scuffs.append({"x": Px.round(x + R.range(-1.0, 1.0)), "t": 0.0}),
		"onCrumble": func(q: Dictionary) -> void:
			splinter(q.x, 0.0, q.vx, 3)
			ps.spawn(P.VAPOUR, q.x, -1.0, R.range(-10.0, 14.0), -R.range(2.0, 6.0), R.range(0.4, 0.7), C[6], R.range(1.2, 2.0)),
	})
	veins = []
	bubbles = []
	for k in 3:
		var x := R.range(-12.0, 8.0)
		var y := R.range(-24.0, -6.0)
		var a := R.range(0.0, TAU)
		for i in 9:
			a += R.range(-0.6, 0.6)
			x += cos(a) * 1.5
			y += sin(a) * 1.2
			if x < -14.0 or x > 10.0 or y < -26.0 or y > -2.0:
				break
			veins.append([floorf(x), floorf(y)])
	for k in 5:
		bubbles.append([R.int_(-12, 8), R.int_(-23, -4), 1 if R.chance(0.4) else 0])
	cracks = Lib.fractures(R, inside, HIT_AT[0] + 1, HIT_AT[1], 4, {"len": 8.0, "a0": -0.9, "spread": 1.9})
	cracks2 = Lib.fractures(R, inside, HIT_AT[0] + 1, HIT_AT[1], 6, {"len": 18.0, "a0": -1.3, "spread": 2.7, "fork": 0.16})


func jolt() -> float:
	return 2.0 if (t >= HIT and t < HIT + 0.05) else (1.0 if (t >= HIT + 0.05 and t < HIT + 0.12) else ((1.0 if floori(t * 40.0) % 2 else 0.0) if (t >= SHIVER and t < FLASH) else 0.0))


# the block: shaded faces, frost veins and bubbles inside, lit edges, a dark rim
func drawBlock(p: Px.Painter) -> void:
	if t >= BURST:
		return
	var jx := jolt()
	var wh := t >= FLASH
	var sweep := -40.0 + 70.0 * Px.seg(t, 0.04, 0.3)
	var sh := func(pts: Array) -> Array: return pts.map(func(q: Array) -> Array: return [q[0] + jx, q[1]])
	# rim
	p.poly(sh.call([[-17, 1], [-17, -28.5], [-8.3, -35.2], [21, -35.2], [21, -5.6], [12.5, 1]]), C[0])
	if wh:
		p.poly(sh.call(SIL), WHITE)
		return
	# the front: lit at the top, deep at the foot, the far edges showing through, a fracture plane catching
	# light, reflections streaked across the upper left
	p.poly(sh.call(FRONT), func(x: float, y: float) -> int:
		var lx := x - jx
		var d := lx + y * 0.8
		if absf(d - sweep) < 1.3 and y < -6.0:
			return WHITE
		if y < -9.0 and (absf(d + 21.0) < 1.1 or absf(d + 16.5) < 0.6):
			return C[6]
		if ((absf(lx + 7.5) < 0.5 and y < -6.0) or (absf(y + 5.5) < 0.5 and lx > -8.0)) and (floori(lx) + floori(y)) % 2 == 0:
			return C[5]
		if Lib.inPoly(PLANE, lx, y):
			return C[6] if y < -25.5 else C[5]
		if Lib.inPoly(SHADE, lx, y):
			return C[3]
		return C[5] if y < -25.5 else (C[4] if y < -8.0 else (C[3] if y < -2.5 else C[2])))
	p.poly(sh.call(TOP), func(x: float, y: float) -> int: return C[7] if y > -29.5 else (C[5] if y < -32.5 else (C[7] if Px.rand(floorf(x), floorf(y), 3) < 0.08 else C[6])))
	p.poly(sh.call(SIDE), func(x: float, y: float) -> int:
		var lx := x - jx
		return C[3] if lx < 13.5 else (C[3] if (absf(lx - 16.5) < 0.6 and y < -8.0) else (C[1] if y > (lx - 12.0) * -0.75 - 3.0 else C[2])))
	for v: Array in veins:
		p.px(v[0] + jx, v[1], C[5])
	for b: Array in bubbles:
		p.px(b[0] + jx, b[1], C[6])
		if b[2]:
			p.px(b[0] + jx + 1.0, b[1], C[5])
			p.px(b[0] + jx, b[1] + 1, C[5])
	var E := func(a: Array, b: Array, c: int) -> void: p.line(a[0] + jx, a[1], b[0] + jx, b[1], c)
	E.call([-16, -28], [12, -28], WHITE)
	E.call([-16, -28], [-8, -34], C[6])
	E.call([-8, -34], [20, -34], C[5])
	E.call([12, -28], [20, -34], C[7])
	E.call([-16, -1], [-16, -28], C[5])
	E.call([12, -1], [12, -28], C[6])
	E.call([20, -6], [20, -34], C[3])
	E.call([13, -1], [20, -6], C[1])
	if t >= HIT:
		Lib.drawFractures(p, cracks, (t - HIT) * 170.0, C, {"ox": jx})
	if t >= CRACK2:
		Lib.drawFractures(p, cracks2, (t - CRACK2) * 200.0, C, {"ox": jx})


# the floor: a frost patch where the block stands, frost scuffed along by sliding chunks
func drawFloor(p: Px.Painter) -> void:
	var out := 1.0 - Px.smooth(BURST + 0.6, BURST + 1.5, t)
	if out > 0.0:
		for x in range(-22, 27):
			var d := absf(x - 2) / 24.0
			var h := Px.rand(x, 41)
			var a := out * Px.clamp((1.1 - d) / 0.25)
			if a <= 0.0:
				continue
			p.dot(x, 0.0, WHITE if h < 0.35 else C[6], a)
			if h < 0.4 and (x < -16 or x > 20):
				p.dot(x, -1.0, C[5], a)
			var j := 1
			while j <= 1.0 + Px.round(Px.rand(x, 7) * 3.0 * (1.0 - d)):
				p.dot(x, j, C[5] if j < 2 else C[4], a * (1.0 - j / 5.0))
				j += 1
	for s: Dictionary in scuffs:
		var a: float = 1.0 - s.t / 0.9
		if a > 0.0:
			p.dot(s.x, 0.0, WHITE if s.t < 0.15 else C[6], a)
			p.dot(s.x, 1.0, C[4], a * 0.6)


# chunks of each face, cut at random, flung away from the hit, mostly right and up
func chop(pts: Array, mx: float, depth: int) -> Array:
	var c := Lib.centroid(pts)
	if c.area < mx or depth > 4:
		return [pts]
	var out := []
	for q: Array in Lib.splitPoly(pts, c.x + R.range(-1.0, 1.0), c.y + R.range(-1.0, 1.0), R.range(0.0, PI)):
		out.append_array(chop(q, mx, depth + 1))
	return out


func explode() -> void:
	for e: Array in [[FRONT, 0.6, 46.0], [TOP, 1.0, 40.0], [SIDE, 0.3, 46.0]]:
		var face: Array = e[0]
		var tone: float = e[1]
		var mx: float = e[2]
		for part: Array in chop(face, mx, 0):
			var m := Lib.centroid(part)
			var dx: float = m.x - HIT_AT[0]
			var dy: float = m.y - HIT_AT[1]
			var d := Px.hypot(dx, dy)
			if not d:
				d = 1.0
			var sp := R.range(50.0, 150.0) * (0.7 + 0.3 * (1.0 - d / 40.0))
			panes.add({
				"pts": part.map(func(pt: Array) -> Array: return [pt[0] - m.x, pt[1] - m.y]), "x": m.x, "y": m.y, "vx": (dx / d) * sp * 0.9 + R.range(40.0, 110.0), "vy": (dy / d) * sp * 0.4 - R.range(60.0, 200.0),
				"a": 0.0, "va": R.range(-10.0, 10.0), "f": R.range(-0.9, 0.9), "vf": R.range(-7.0, 7.0), "tone": tone, "lit": tone, "g": 0.9, "drag": 0.5, "bounce": 0.38, "solid": true, "brittle": 3, "crumble": R.range(0.25, 0.6), "life": R.range(1.5, 1.9),
			})
	for i in 46:
		var x := R.range(-15.0, 19.0)
		var y := -R.range(1.0, 33.0)
		var dx: float = x - HIT_AT[0]
		var dy: float = y - HIT_AT[1]
		var d := Px.hypot(dx, dy)
		if not d:
			d = 1.0
		var sp := R.range(60.0, 200.0)
		if not inside(x, y):
			continue
		bits.add({"kind": B.CHUNK if R.chance(0.15) else B.SHARD, "x": x, "y": y, "vx": (dx / d) * sp * 0.8 + R.range(20.0, 90.0), "vy": (dy / d) * sp * 0.4 - R.range(60.0, 240.0), "g": 0.85, "drag": 0.6, "bounce": 0.32, "life": R.range(0.8, 1.4), "a": R.range(0.0, TAU), "va": R.range(-22.0, 22.0), "s": R.range(1.2, 3.4), "c": C[R.int_(4, 7)], "ramp": [C[1], C[3], C[4], C[6], C[7]]})
	# ice dust rolls out along the floor, vapour hangs where it stood, a flurry, glints, a flash of light
	for i in 9:
		ps.spawn(P.VAPOUR, R.range(-6.0, 18.0), -R.range(1.0, 6.0), R.range(10.0, 130.0), -R.range(2.0, 12.0), R.range(0.6, 1.1), C[6], R.range(2.2, 3.8))
	for i in 5:
		ps.spawn(P.DUST, R.range(-6.0, 16.0), -R.range(1.0, 4.0), R.range(30.0, 110.0), -R.range(2.0, 8.0), R.range(0.5, 0.9), C[5], R.range(1.6, 2.8))
	for i in 4:
		ps.spawn(P.VAPOUR, R.range(-8.0, 18.0), -R.range(8.0, 28.0), R.range(-10.0, 50.0), -R.range(8.0, 24.0), R.range(0.6, 1.0), C[6], R.range(2.6, 4.0))
	for i in 16:
		var a := R.range(-PI * 0.9, -0.1)
		var sp := R.range(40.0, 140.0)
		ps.spawn(P.FLAKE, R.range(-8.0, 16.0), -R.range(6.0, 28.0), cos(a) * sp + 20.0, sin(a) * sp, R.range(1.0, 1.6), WHITE if R.chance(0.6) else C[6], R.range(0.5, 1.6))
	for i in 7:
		ps.spawn(P.STAR, R.range(-14.0, 40.0), -R.range(4.0, 40.0), R.range(-8.0, 16.0), -R.range(4.0, 16.0), R.range(0.4, 0.8), WHITE if R.chance(0.5) else C[6], R.range(1.0, 2.4))
	lights.add(2.0, -17.0, 64.0, WHITE, 0.85, 0.14)
	lights.add(16.0, -18.0, 86.0, C[4], 0.5, 0.55)


func update(dt: float) -> void:
	t += dt
	# the hit: a flash on the left face, chips and sparks thrown back, the block jolts
	if not struck and t >= HIT:
		struck = true
		lights.add(HIT_AT[0], HIT_AT[1], 24.0, WHITE, 0.6, 0.08)
		lights.add(HIT_AT[0] + 6, HIT_AT[1], 40.0, C[5], 0.4, 0.3)
		for i in 12:
			var a := PI + R.range(-0.9, 0.9)
			var sp := R.range(50.0, 120.0)
			ps.spawn(P.SPARK, HIT_AT[0] - 1, HIT_AT[1], cos(a) * sp, sin(a) * sp - 40.0, R.range(0.15, 0.4))
		for i in 6:
			var a := PI + R.range(-1.0, 0.8)
			var sp := R.range(40.0, 100.0)
			bits.add({"kind": B.SHARD, "x": HIT_AT[0] - 1.0, "y": HIT_AT[1] + R.range(-2.0, 2.0), "vx": cos(a) * sp, "vy": sin(a) * sp - 60.0, "g": 0.85, "drag": 0.6, "bounce": 0.3, "life": R.range(0.5, 0.9), "a": R.range(0.0, TAU), "va": R.range(-20.0, 20.0), "s": R.range(1.2, 2.4), "c": C[R.int_(5, 7)]})
	if not wave2 and t >= CRACK2:
		wave2 = true
		lights.add(0.0, -16.0, 36.0, C[6], 0.35, 0.15)
		for i in 3:
			bits.add({"kind": B.SHARD, "x": R.range(-14.0, 18.0), "y": -R.range(4.0, 30.0), "vx": R.range(-30.0, 30.0), "vy": -R.range(10.0, 50.0), "g": 0.85, "drag": 0.6, "bounce": 0.3, "life": R.range(0.4, 0.7), "a": R.range(0.0, TAU), "va": R.range(-20.0, 20.0), "s": R.range(1.0, 2.0), "c": C[R.int_(5, 7)]})
	if not white and t >= FLASH:
		white = true
		lights.add(2.0, -17.0, 44.0, WHITE, 0.7, 0.08)
	if not burst and t >= BURST:
		burst = true
		explode()
	# glints wink on the settling debris
	if burst and t < BURST + 1.0 and R.chance(0.08) and bits.list.size():
		var b: Dictionary = R.pick(bits.list)
		ps.spawn(P.STAR, b.x, b.y - 1.0, 0.0, -3.0, R.range(0.2, 0.4), WHITE if R.chance(0.5) else C[6], R.range(0.6, 1.5))
	var i := scuffs.size() - 1
	while i >= 0:
		scuffs[i].t += dt
		if scuffs[i].t > 0.9:
			scuffs.remove_at(i)
		i -= 1
	ps.update(dt)
	bits.update(dt)
	panes.update(dt)
	lights.update(dt)
	Lib.endBy(t, meta.duration, ps, bits, panes)


func drawBack(p: Px.Painter) -> void:
	drawFloor(p)
	ps.draw(p, "back")


func draw(p: Px.Painter) -> void:
	drawBlock(p)
	# the hit: a star and a short flare on the left face
	var h := t - HIT
	if h >= 0.0 and h < 0.2:
		Px.sparkle(p, HIT_AT[0] - 1, HIT_AT[1], 9.0 * Px.Ease.outBack(minf(1.0, h / 0.04)) * (1.0 - h / 0.2), C[6], C[4], 0.7)
		if h < 0.08:
			Px.flare(p, HIT_AT[0] - 1, HIT_AT[1], 14.0 * (1.0 - h / 0.08), 1.0 - h / 0.08, C)
	# cold light in the ice, brighter as it cracks; a pool on the floor
	var k := 1.0 - Px.smooth(BURST, BURST + 0.4, t)
	var crk := Px.smooth(HIT, FLASH, t)
	if k > 0.0:
		p.glow(2.0, -17.0, 34.0, C[4], (0.16 + 0.22 * crk) * k)
		p.glow(2.0, -2.0, 30.0, C[4], 0.14 * k)
	if t >= FLASH and t < BURST + 0.12:
		Px.flare(p, 2.0, -17.0, 26.0 * (1.0 - Px.clamp((t - FLASH) / 0.18)), 1.0 - Px.clamp((t - FLASH) / 0.18), C)
	panes.draw(p, C)
	bits.draw(p)
	ps.draw(p, "front")
	lights.draw(p)
