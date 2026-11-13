# The breakup (the outline flickering on, a white hero frame, the body bursting into bits of light) follows
# Sprite Fusion's open-source blink (https://www.spritefusion.com/pixel-art-vfx/movement), MIT License,
# Copyright (c) 2026 Hugo Duprez.
# port-of: src/fx/scifi/warp-out.js@11d867a9736ea97afe05593cbe613bc402480c36
extends "../../core/effect.gd"

const Px := preload("../../core/px.gd")
const P := Px.P
const WHITE := Px.WHITE

static var meta := {
	"name": "Warp out",
	"desc": "The hero's outline flickers on, they flash white and break into light from the head down, streaming up a beam that lifts off the floor and pinches shut.",
	"tags": ["scifi", "teleport", "warp", "beam", "despawn", "leave", "one-shot"],
	"size": [128, 168],
	"origin": [64, 128],
	"duration": 2.6,
	"loop": false,
	"fps": 30,
	"bg": "ground",
	"actor": 2,
	"options": {"palette": ["#0b1030", "#152a63", "#1d4f9e", "#2582d2", "#36b9ee", "#8ae8ff", "#d4fbff", "#ffffff"], "seed": 4},
}

static var SET := {"turn": 1, "crouch": 3, "fx": -9, "fy": -15, "bx": 10, "by": -15, "ffx": -3, "fbx": 4}
static var RAISED := Px.merge(SET, {"crouch": 0, "fx": -11, "fy": -29, "bx": 12, "by": -29})
static var act := {
	"onBody": true,
	"follow": 0,
	"poses": [
		[-0.3, Px.READY],
		[0.1, SET],
		[0.42, RAISED, "snap"],
		[2.6, RAISED],
	],
}

# the beats: it charges, flashes white, breaks up into the beam, the beam lifts away
const FLASH := 0.42
const BREAK0 := 0.5
const BREAK1 := 1.1
const LIFT := 1.3
const GONE := 1.62
static var TOP: float = -meta.origin[1]


static func actorAlpha(t: float, _o: Dictionary) -> float:
	return 1.0 if t < FLASH else 0.0


var C: Array
var R: Px.Rng
var A: Dictionary
var ps: Px.Particles
var lights: Px.Lights
var bits: Array = []
var edge: Array = []
var t := 0.0
var flashed := false
var lifted := false


func on(x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < A.w and y < A.h and A.mask.data[y * A.w + x]


func create(o: Dictionary) -> void:
	C = Px.fit(o.palette, 8)
	R = Px.Rng.new(o.seed)
	A = o.actor
	ps = Px.Particles.new({"rng": R, "ground": func(): return 0.0, "sparks": [WHITE, C[6], C[5], C[4]]})
	lights = Px.Lights.new()
	# the body: every pixel, its own color, whether it's on the edge, when it lets go (head first)
	var Aw: int = A.w
	var Ah: int = A.h
	var pixels: PackedInt32Array = A.pixels
	for my in range(-1, Ah + 1):
		for mx in range(-1, Aw + 1):
			if on(mx, my):
				var x: float = A.x + mx
				var y: float = A.y + my
				var tr := BREAK0 + (my / float(Ah)) * (BREAK1 - BREAK0 - 0.12) + R.range(0.0, 0.12)
				var rim := not on(mx - 1, my) or not on(mx + 1, my) or not on(mx, my - 1) or not on(mx, my + 1)
				var pc := pixels[my * Aw + mx]
				bits.append({"x": x, "y": y, "x0": x, "y0": y, "vx": 0.0, "vy": 0.0, "tr": tr, "c": pc if pc else C[3], "free": false, "j": R.next(), "rim": rim})
			elif on(mx - 1, my) or on(mx + 1, my) or on(mx, my - 1) or on(mx, my + 1):
				edge.append([A.x + mx, A.y + my])


# the beam's half width and how far its foot has lifted off the floor
func width() -> float:
	return 0.0 if t < BREAK0 else (2.0 + 7.0 * Px.Ease.outCubic(Px.clamp((t - BREAK0) / 0.35)) if t < LIFT else Px.lerp(9.0, 0.6, Px.Ease.inCubic(Px.clamp((t - LIFT) / (GONE - LIFT)))))


func foot() -> float:
	return 0.0 if t < LIFT else Px.lerp(0.0, TOP, Px.Ease.inQuad(Px.clamp((t - LIFT) / (GONE - LIFT))))


func update(dt: float) -> void:
	t += dt
	# charging: motes gather to the body, the floor target closes in
	if t < FLASH - 0.05 and R.chance(0.7):
		var a := R.range(0.0, TAU)
		var D := R.range(26.0, 48.0)
		var T := R.range(0.16, 0.26)
		var v := (D * 3.0) / (exp(3.0 * T) - 1.0)
		var cy := -19.0
		ps.spawn(P.STREAK, cos(a) * D, cy + sin(a) * D * 0.8, -cos(a) * v, -sin(a) * v * 0.8, T, C[6] if R.chance(0.5) else C[5])
	if t >= FLASH and not flashed:
		flashed = true
		lights.add(0.0, -20.0, 80.0, C[4], 0.9, 0.5)
		lights.add(0.0, -20.0, 30.0, WHITE, 0.8, 0.12)
		for i in 14:
			ps.spawn(P.STAR, R.range(-14.0, 14.0), -R.range(2.0, 40.0), R.range(-20.0, 20.0), -R.range(10.0, 40.0), R.range(0.3, 0.6), WHITE if R.chance(0.5) else C[6], R.range(0.8, 1.8))
	# the body lets go bit by bit: a little burst outward, then hauled up the beam, drawn in to its middle
	var i := bits.size() - 1
	while i >= 0:
		var b: Dictionary = bits[i]
		if t < b.tr:
			i -= 1
			continue
		if not b.free:
			b.free = true
			var ox: float = b.x + 0.5
			var oy: float = b.y + 19.0
			b.vx = ox * R.range(1.5, 4.0) + R.range(-10.0, 10.0)
			b.vy = oy * R.range(0.5, 1.5) - R.range(10.0, 40.0)
		b.vy -= 560.0 * dt
		b.vx += (-(b.x + 0.5) * 14.0 - b.vx * 3.0) * dt
		b.x += b.vx * dt
		b.y += b.vy * dt
		if b.y < TOP + 2.0:
			bits.remove_at(i)
		i -= 1
	if t >= LIFT and not lifted:
		lifted = true
		lights.add(0.0, -2.0, 40.0, C[4], 0.7, 0.3)
		for j in 22:
			var a := -PI / 2.0 + R.range(-1.4, 1.4)
			var sp := R.range(80.0, 220.0)
			ps.spawn(P.SPARK, R.range(-3.0, 3.0), -1.0, cos(a) * sp, sin(a) * sp, R.range(0.2, 0.55))
		for j in 16:
			ps.spawn(P.STAR, R.range(-10.0, 10.0), -R.range(4.0, 70.0), R.range(-6.0, 6.0), -R.range(10.0, 30.0), R.range(0.5, 0.95), WHITE if R.chance(0.4) else C[6], R.range(0.6, 1.6), R.range(0.0, 0.3))
	ps.update(dt)
	lights.update(dt)


func drawBack(p: Px.Painter) -> void:
	# the floor target: a ring closing in on the feet, then the beam's foot glowing
	var k := Px.clamp(t / FLASH)
	var fade := 1.0 - Px.smooth(LIFT, LIFT + 0.6, t)
	if fade > 0.0:
		Px.band(p, 0.0, 0.0, Px.lerp(30.0, 14.0, Px.Ease.outCubic(k)), 0.16, 1.5, (0.4 + 0.6 * k) * fade, [C[3], C[4], C[5], C[6]], func(g: float) -> bool: return sin(g) < 0.0)
	# the beam: thin bright walls, a glassy inside, from its foot to the sky
	var w := width()
	var f := foot()
	if w > 0.3 and t < GONE:
		var y := floorf(TOP)
		while y < f + (0.0 if t < LIFT else 0.0):
			if y >= f and t >= LIFT:
				break
			var x := floorf(-w) - 1.0
			while x <= ceilf(w):
				var q := absf(x + 0.5) / w
				if q > 1.0 + 1.0 / w:
					x += 1.0
					continue
				if w < 2.2:
					p.px(x, y, WHITE if q < 0.7 else C[6])
				elif q > 1.0:
					p.dot(x, y, C[4], 0.5)
				elif q > 1.0 - 1.2 / w:
					p.px(x, y, C[6])
				else:
					p.blend(x + 0.5, y + 0.5, C[5], 0.12 + 0.25 * q * q)
				x += 1.0
			if (int(y) & 7) == 0:
				p.glow(0.0, y, minf(w * 2.5 + 6.0, y - TOP + 2.0), C[4], 0.28)
			y += 1.0
	ps.draw(p, "back")


func draw(p: Px.Painter) -> void:
	var k := Px.clamp(t / FLASH)
	var fade := 1.0 - Px.smooth(LIFT, LIFT + 0.6, t)
	if fade > 0.0:
		Px.band(p, 0.0, 0.0, Px.lerp(30.0, 14.0, Px.Ease.outCubic(k)), 0.16, 1.5, (0.4 + 0.6 * k) * fade, [C[3], C[5], C[6], WHITE], func(g: float) -> bool: return sin(g) >= 0.0)
	# charging: the outline flickers on round the hero, denser as it builds
	if t < FLASH:
		var fr := floori(t * 24.0)
		for xy: Array in edge:
			var x: int = xy[0]
			var y: int = xy[1]
			if Px.rand(x, y, fr) < 0.25 + 0.7 * k:
				p.px(x, y, WHITE if (k > 0.7 and Px.rand(x, y, fr, 1) < 0.5) else C[5])
		p.glow(0.0, -20.0, 26.0, C[4], 0.4 * k)
	# the body, still held together: white in the flash, then cooling to the beam's color as it waits its turn
	for b: Dictionary in bits:
		if b.free or t < FLASH:
			continue
		# white in the flash, then light with the body's own shading under it, a bright rim, a rolling scanline
		var a := t - FLASH
		var scan := posmod(int(b.y) + floori(t * 40.0), 4) == 0
		var c: int = WHITE if a < 0.07 else (C[6] if a < 0.16 else (C[6] if b.rim else Px.mix(b.c, C[6] if scan else C[5], 0.6 if scan else 0.45)))
		p.px(b.x, b.y, WHITE if b.tr - t < 0.06 else c)
	# the bits on their way up: streaks, longer the faster they go, cooling as they climb
	for b: Dictionary in bits:
		if not b.free:
			continue
		var sp := absf(b.vy)
		var L := minf(8.0, sp * 0.02)
		var u := Px.clamp((b.y - TOP) / (b.y0 - TOP))
		var head: int = WHITE if u > 0.75 else (C[6] if u > 0.4 else C[5])
		# one in three draws a streak, the rest a single spark, so the stream reads as light, not static
		if L >= 1.0 and b.j < 0.33:
			p.line(b.x, b.y, b.x - b.vx * 0.01, b.y + L, func(s: float): return head if s < 0.25 else (C[5] if s < 0.6 else C[3]))
		elif b.j < 0.75 or u > 0.6:
			p.px(b.x, b.y, WHITE if b.j > 0.9 else head)
	if t >= FLASH and t < FLASH + 0.12:
		Px.sparkle(p, 0.0, -20.0, 10.0 * (1.0 - (t - FLASH) / 0.12), C[6], C[5], 0.6)
	ps.draw(p, "front")
	lights.draw(p)
