# The flickering outline, the white silhouette flash and the body's own pixels flying off as bits of light are
# adapted from Sprite Fusion's open-source movement (https://www.spritefusion.com/pixel-art-vfx/movement),
# MIT License, Copyright (c) 2026 Hugo Duprez.
# port-of: src/fx/spawn/disintegrate.js@adaf697b58c9a48d8f6ea83157dccda897e824c6
extends "../../core/effect.gd"

const Px := preload("../../core/px.gd")
const Lib := preload("_lib.gd")
const P := Px.P
const WHITE := Px.WHITE

static var meta := {
	"name": "Disintegrate",
	"desc": "The character crackles with light, flashes white, then peels away from the head down: each pixel flares white-hot and streams off on the wind as a cooling mote of light.",
	"tags": ["spawn", "death", "disintegrate", "dissolve", "pixels", "energy", "light", "one-shot"],
	"size": [176, 100],
	"origin": [48, 86],
	"duration": 3.4,
	"loop": false,
	"fps": 30,
	"bg": "ground",
	"actor": 2,
	"options": {
		"palette": ["#120a26", "#2a1658", "#3d2f9c", "#3f68d4", "#3fa8ec", "#86e0ff", "#d6f8ff", "#ffffff"],
		"accent": ["#7a3ae4", "#b682ff", "#ecd2ff"],
		"wind": 1,
		"seed": 5,
	},
}

static var AGONY := {"turn": 1.15, "crouch": 0, "hy": -1, "fx": -14, "fy": -36, "bx": 15, "by": -36, "ffx": -3, "fbx": 4}
static var act := {
	"onBody": true,
	"poses": [
		[-0.2, Px.READY],
		[0.05, {"turn": 1, "crouch": 3, "fx": -9, "fy": -16, "bx": 10, "by": -16, "ffx": -3, "fbx": 4}],
		[0.3, AGONY],
		[3.4, AGONY],
	],
}

const FLASH := 0.42
const WHITE_T := 0.07
const P0 := FLASH + WHITE_T
const PEEL := 1.2
const CORE_Y := -20.0
static func actorAlpha(t: float, _o: Dictionary) -> float:
	return 1.0 if t < FLASH - 0.1 else 0.0


var C: Array
var A: Array
var R: Px.Rng
var W: float
var COOL: Array
var body: Lib.Body
var rim: Array
var top: float
var H: float
var ps: Px.Particles
var lights: Px.Lights
var motes: Array = []
var t := 0.0
var flashed := false


func create(o: Dictionary) -> void:
	C = Px.fit(o.palette, 8)
	A = Px.fit(o.accent, 3)
	R = Px.Rng.new(o.seed)
	W = o.wind
	var floor_ := func(): return 0.0
	# what a mote cools through after its white flare: the main ramp, or the accent for variety
	COOL = [[C[6], C[5], C[5], C[4]], [A[2], A[1], A[1], A[0]], [WHITE, C[6], C[5], C[5]]]
	body = Lib.bodyOf(o.actor, C)
	rim = Lib.rimOf(body)
	top = body.y
	H = body.h
	ps = Px.Particles.new({"rng": R, "ground": floor_, "sparks": [C[7], C[6], C[5], C[3]]})
	lights = Px.Lights.new()
	# when each pixel lets go: row by row from the crown, a ragged front, the rim a beat before the middle
	for b in body.list:
		var u: float = (b.y - top) / H
		b.key = u + 0.14 * (Px.rand(b.mx, b.my, 3) - 0.5) + 0.05 * Px.noise(b.mx * 0.45, 7) - (0.03 if b.edge else 0.0)
		b.gone = false


func front(tt: float) -> float:
	return -0.06 + 1.14 * Px.Ease.inOutSine(Px.clamp((tt - P0) / PEEL))


# the wind: a steady push with gusts, and a slow swirl so neighbouring motes travel in sheets
func gust(tt: float) -> float:
	return 0.7 + 0.5 * (Px.noise(tt * 1.6, 11) * 0.5 + 0.5)


func letGo(b: Dictionary) -> void:
	b.gone = true
	var lo: bool = b.y > -9.0 and R.chance(0.22)
	var kind := 2 if lo else (1 if R.chance(0.42) else (3 if R.chance(0.07) else 0))
	if kind == 3:
		ps.spawn(P.STAR, b.x, b.y, R.range(-6.0, 14.0) * W, R.range(-26.0, -8.0), R.range(0.6, 1.1), C[6] if R.chance(0.5) else WHITE, R.range(1.0, 2.2))
		return
	var life := R.range(0.7, 1.2) if kind == 2 else (R.range(0.25, 0.5) if kind == 1 else R.range(0.9, 1.7))
	# a pop off the body, outward from its middle and up, before the wind takes it
	var out: float = (b.x + 0.5) * R.range(2.0, 6.0)
	motes.append({
		"x": b.x + 0.5, "y": b.y + 0.5, "vx": (out + R.range(-6.0, 16.0)) * (0.4 if kind == 2 else 1.0), "vy": R.range(-30.0, -8.0) if kind == 2 else R.range(-46.0, -8.0),
		"life": life, "max": life, "c": b.c, "kind": kind, "lift": R.range(0.4, 1.4), "cool": COOL[1 if R.chance(0.3) else (2 if R.chance(0.3) else 0)], "own": R.chance(0.2), "rest": false, "seed": R.range(0.0, 100.0),
	})


func update(dt: float) -> void:
	t += dt
	# the charge: light gathers into the body in streaks
	if t < FLASH - 0.05 and R.chance(0.55):
		var a := R.range(0.0, TAU)
		var D := R.range(22.0, 44.0)
		var T := R.range(0.16, 0.26)
		var v := (D * 3.0) / (Px.exp(3.0 * T) - 1.0)
		var x := cos(a) * D
		var y := minf(CORE_Y + sin(a) * D * 0.9, -3.0)
		var l := Px.hypot(x, y - CORE_Y)
		if not l:
			l = 1.0
		ps.spawn(P.STREAK, x, y, (-x / l) * v, ((CORE_Y - y) / l) * v, T, C[6] if R.chance(0.5) else C[5])
	if not flashed and t >= FLASH:
		flashed = true
		lights.add(0.0, CORE_Y, 64.0, C[4], 0.85, 0.6)
		lights.add(0.0, CORE_Y, 30.0, WHITE, 0.8, 0.14)
		for i in 14:
			var a := R.range(0.0, TAU)
			var sp := R.range(50.0, 150.0)
			ps.spawn(P.STAR, R.range(-6.0, 6.0), CORE_Y + R.range(-10.0, 10.0), cos(a) * sp, sin(a) * sp * 0.7 - 25.0, R.range(0.35, 0.8), R.pick([WHITE, C[6], C[5]]), R.range(0.6, 1.8))
	# the peel front eats the body
	if t >= P0:
		var f := front(t)
		for b in body.list:
			if not b.gone and b.key < f:
				letGo(b)
	# the wind drops once the body is gone, and the last motes hang in the air
	var g := gust(t) * (1.0 - 0.55 * Px.smooth(P0 + PEEL, P0 + PEEL + 1.2, t))
	var i := motes.size() - 1
	while i >= 0:
		var m: Dictionary = motes[i]
		m.life -= dt
		if m.life <= 0.0:
			motes.remove_at(i)
			i -= 1
			continue
		if m.kind == 2:
			# heavier ash: drifts a little, falls, settles on the floor and glows out
			if m.rest:
				i -= 1
				continue
			m.vx += (W * 30.0 * g - m.vx * 1.2) * dt
			m.vy += 260.0 * dt - m.vy * 1.2 * dt
			m.x += m.vx * dt
			var ny: float = m.y + m.vy * dt
			if m.vy > 0.0 and ny >= -0.5:
				if m.vy > 50.0:
					m.vy *= -0.35
					m.vx *= 0.6
					m.y = -0.6
				else:
					m.rest = true
					m.y = -0.5
			else:
				m.y = ny
			i -= 1
			continue
		var age: float = m.max - m.life
		var k := minf(1.0, age / 0.15)
		var fx := W * (100.0 * g + 30.0 * Px.noise2(m.x * 0.07, m.y * 0.07 - t * 0.8, 3)) * k
		var fy: float = (-30.0 * m.lift + 42.0 * Px.noise2(m.x * 0.06 + 40.0, m.y * 0.06 - t * 1.1, 5)) * k
		var drag := 3.0 if m.kind == 1 else 1.5
		m.vx += (fx - m.vx * drag) * dt
		m.vy += (fy - m.vy * drag) * dt
		m.x += m.vx * dt
		m.y += m.vy * dt
		i -= 1
	ps.update(dt)
	lights.update(dt)


func drawBack(p: Px.Painter) -> void:
	# the floor ring from the flash, far half
	var k := (t - FLASH) / 0.5
	if k > 0.0 and k < 1.0:
		Px.band(p, 0.0, 0.0, 6.0 + 30.0 * Px.Ease.outCubic(k), 0.18, maxf(1.0, 3.5 * (1.0 - k)), 1.15 - k, C, func(g: float) -> bool: return sin(g) < 0.0, k < 0.12)
	# a cold pool on the floor while the body burns away
	var pool := Px.smooth(0.1, FLASH, t) * (1.0 - Px.smooth(P0 + PEEL * 0.8, P0 + PEEL + 0.6, t))
	if pool > 0.0:
		p.glow(0.0, -1.0, 30.0, C[4], 0.22 * pool)


func draw(p: Px.Painter) -> void:
	var f := front(t)
	# charge: a crackling outline that thickens, the rim of the body catching light
	if t < FLASH:
		var k := t / FLASH
		var fr := floori(t * 30.0)
		for c in rim:
			var h := Px.rand(c.mx * 61 + c.my, fr, 7)
			if h < 0.12 + 0.62 * k * k:
				p.px(c.x, c.y, WHITE if (k > 0.72 and Px.rand(c.mx, c.my, fr) < 0.5) else (C[6] if h < 0.2 else C[5]))
		p.glow(0.0, CORE_Y, 26.0, C[4], 0.42 * k)
		p.glow(0.0, CORE_Y, 12.0, C[6], 0.25 * k * k)
	# the body: drawn by us from the shudder on, flashing white, then charged, glowing hot at the front
	if t >= FLASH - 0.1:
		var shake := (1.0 if floori(t * 60.0) % 2 else -1.0) * 0.6 if t < FLASH else 0.0
		var white := t >= FLASH and t < P0
		for b in body.list:
			if b.gone:
				continue
			var c: int
			if white:
				c = C[6] if b.edge else WHITE
			elif t < FLASH:
				c = Px.mix(b.c, C[6], 0.7) if b.edge else Px.mix(b.c, C[5], 0.25)
			else:
				var d: float = b.key - f
				var above: bool = not body.on(b.mx, b.my - 1) or body.cell(b.mx, b.my - 1).gone
				c = WHITE if (above and d < 0.06) else (Px.mix(b.c, C[6], 0.7) if d < 0.03 else (Px.mix(b.c, C[5], 0.4) if d < 0.1 else (Px.mix(b.c, C[5], 0.5) if b.edge else Px.mix(b.c, C[4], 0.16))))
			p.px(b.x + shake, b.y, c)
		if white:
			p.glow(0.0, CORE_Y, 34.0, C[5], 0.7)
			Px.sparkle(p, 0.0, CORE_Y - 3.0, 9.0, C[6], C[4], 0.5)
	# light rides the peel front down the body
	if t >= P0 and f < 1.05:
		var fy := top + Px.clamp(f) * H
		var k := 1.0 - Px.smooth(0.85, 1.05, f)
		p.glowLine(-10.0, fy, 10.0, fy, 8.0, C[5], 0.32 * k)
		p.glow(0.0, fy, 22.0, C[4], 0.2 * k)
	# the floor ring, near half
	var k := (t - FLASH) / 0.5
	if k > 0.0 and k < 1.0:
		Px.band(p, 0.0, 0.0, 6.0 + 30.0 * Px.Ease.outCubic(k), 0.18, maxf(1.0, 3.5 * (1.0 - k)), 1.15 - k, C, func(g: float) -> bool: return sin(g) >= 0.0, k < 0.12)
	# the motes: flare white, cool down the ramp, leave a short tail, dither out
	for m in motes:
		var age: float = m.max - m.life
		var k2: float = m.life / m.max
		var a := k2 / 0.35 if k2 < 0.35 else 1.0
		var c: int
		if age < 0.034:
			c = Px.mix(m.c, WHITE, 0.55)
		elif age < 0.06:
			c = WHITE
		elif age < 0.15:
			c = m.cool[0]
		else:
			var u: float = (age - 0.15) / maxf(0.05, m.max - 0.15)
			var cc: int = m.cool[1 + mini(2, floori(u * 3.0))]
			c = Px.mix(m.c, cc, 0.55) if (m.own and u < 0.5) else cc
			if m.kind == 0 and sin(t * 21.0 + m.seed) > 0.8:
				c = m.cool[0]
		if m.kind == 2:
			p.dot(m.x, m.y, c, a)
			p.glow(m.x, m.y, 3.0, C[5], 0.3 * k2)
			continue
		var sp := Px.hypot(m.vx, m.vy)
		var ux: float = m.vx / (sp if sp else 1.0)
		var uy: float = m.vy / (sp if sp else 1.0)
		if sp > 30.0 and m.kind == 0:
			p.dot(m.x - ux * 1.2, m.y - uy * 1.2, Px.scale(c, 0.6), a * 0.85)
		if sp > 85.0 and m.kind == 0:
			p.dot(m.x - ux * 2.4, m.y - uy * 2.4, Px.scale(c, 0.4), a * 0.6)
		p.dot(m.x, m.y, c, a)
		if k2 > 0.15:
			p.glow(m.x, m.y, 2.5, c, (0.16 if m.kind == 1 else 0.11) * k2)
	ps.draw(p)
	lights.draw(p)
