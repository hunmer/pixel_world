# The tint that floods the character and the gas round it are adapted from Sprite Fusion's open-source poison
# aura (https://www.spritefusion.com/pixel-art-vfx/poison), MIT License, Copyright (c) 2026 Hugo Duprez.
# port-of: src/fx/shadow/curse.js@882315bee79ce16c16f956a0a15a80c3d3a906c3
extends "../../core/effect.gd"

const Px := preload("../../core/px.gd")
const Lib := preload("_lib.gd")
const P := Px.P
const B := Px.B
const PK := Lib.PK
const WHITE := Px.WHITE

static var meta := {
	"name": "Curse",
	"desc": "Wisps gather over the head, a skull stamps down with a flash, its eyes burn as the curse floods the body violet, then it cracks and crumbles.",
	"tags": ["shadow", "curse", "debuff", "skull", "status", "dark", "magic", "one-shot"],
	"size": [112, 124],
	"origin": [56, 108],
	"duration": 3.4,
	"loop": false,
	"fps": 30,
	"bg": "ground",
	"actor": 2,
	"options": {"palette": Lib.VOID, "bone": ["#170f26", "#4a3a6e", "#7f6ea6", "#b3a4d4", "#e2d8f6"], "seed": 9},
}

static var COWER := {"turn": 1, "crouch": 6, "lean": 2, "hy": 1, "fx": -6, "fy": -38, "bx": 7, "by": -38, "ffx": -4, "fbx": 5}
static var act := {
	"onBody": true,
	"poses": [
		[-0.2, Px.READY],
		[0.3, {"turn": 0.9, "hy": -1, "fx": -9, "fy": -19, "bx": 10, "by": -19, "ffx": -3, "fbx": 4}],
		[0.55, COWER, "snap"],
		[0.8, Px.merge(COWER, {"crouch": 7})],
		[1.2, Px.merge(COWER, {"crouch": 6, "lean": 3})],
		[1.72, Px.merge(COWER, {"crouch": 7, "lean": 2})],
		[2.1, {"turn": 1, "crouch": 4, "lean": 3, "hy": 2, "fx": -8, "fy": -15, "bx": 9, "by": -15, "ffx": -4, "fbx": 5}],
		[2.9, {"turn": 1, "crouch": 3, "lean": 1, "fx": -8, "fy": -16, "bx": 9, "by": -16, "ffx": -3, "fbx": 4}],
		[3.4, Px.READY],
	],
	"hits": [{"t": 0.55, "stop": 0.09, "shake": 0.2, "amp": 2}],
}

# where the skull hangs, and the beats: it stamps in, burns, cracks, breaks
const SY := -60.0
const STAMP := 0.55
const CRACK := 1.72
const BREAK := 1.98

# the skull, drawn by hand (light from the upper left): k outline, d m l h bone dark to bright, e sockets,
# n nose, t teeth, g the gaps between them
const SKULL := [
	"......kkkkk......",
	"....kkhhhhlkk....",
	"...khhhhhhlllk...",
	"..khhhhhllllllk..",
	".khhhhlllllllmmk.",
	".khhhllllllllmmk.",
	"khhllllllllllmmdk",
	"khlldddllldddmmdk",
	"khleeeeelleeeeedk",
	"kleeeeeelleeeeedk",
	"kleeeeeemleeeeedk",
	"kmleeeelmmleeedkk",
	".kmmlllmnnmlmddk.",
	"..kmmlmnnnnmddk..",
	"..kdmlllmmlmddk..",
	"...kgtgtgtgtgk...",
	"...kdgtgtgtgdk...",
	"....kkkkkkkkk....",
]
const SW := 17
const SH := 18
const EYES := [[-3.5, 1.5], [3.5, 1.5]]


static func inSkull(u: int, v: int) -> bool:
	return u >= 0 and v >= 0 and u < SW and v < SH and SKULL[v][u] != "."


# cracks: jagged paths from the crown down to the sockets and out to the temple, each pixel with its turn to split
static func _cracks() -> Dictionary:
	var out := {}
	var paths := [[[8, 1], [7, 3], [8, 5], [6, 6], [5, 7]], [[9, 1], [10, 3], [10, 4], [12, 6], [12, 7]], [[4, 3], [3, 5], [2, 6]], [[13, 4], [14, 6]]]
	for path: Array in paths:
		var n := 0
		var len := path.size() - 1
		for k in len:
			var x0: int = path[k][0]
			var y0: int = path[k][1]
			var x1: int = path[k + 1][0]
			var y1: int = path[k + 1][1]
			var steps := maxi(absi(x1 - x0), absi(y1 - y0))
			for s in steps + 1:
				var x := Px.roundi(x0 + float((x1 - x0) * s) / steps)
				var y := Px.roundi(y0 + float((y1 - y0) * s) / steps)
				var key := y * SW + x
				if not out.has(key):
					out[key] = (k + float(s) / maxi(1, steps)) / float(len)
				n += 1
	return out


static var CRACKS := _cracks()


# the skull at scale s (squashed by sq as it lands), shaken by (ox, oy); white for the stamp's first frames;
# crack 0..1 splits it from the crown, light leaking out of the splits
static func skull(p: Px.Painter, C: Array, K: Array, s: float, sq: float, ox: float, oy: float, white: bool, crack: float) -> void:
	var PAL := {"k": K[0], "d": K[1], "m": K[2], "l": K[3], "h": K[4], "e": C[0], "n": C[0], "t": K[3], "g": K[0]}
	var cx := ox
	var cy := SY + oy
	var hw := (SW / 2.0) * s + 1.0
	var hh := (SH / 2.0) * s * sq + 1.0
	p.shade(cx - hw, cy - hh, cx + hw, cy + hh, func(x, y):
		var u := floori((x - cx) / s + SW / 2.0)
		var v := floori((y - cy) / (s * sq) + SH / 2.0)
		if not inSkull(u, v):
			return null
		var ch: String = SKULL[v][u]
		if white:
			return C[5] if (ch == "e" or ch == "n") else WHITE
		var ck: Variant = CRACKS.get(v * SW + u)
		if ck != null and ck < crack:
			return C[6] if (crack > 0.55 and (u + v) % 2) else K[0]
		return PAL[ch])


# a socket burning: tongues of violet flame from a white root, licking up out of the eye
static func eyeFire(p: Px.Painter, C: Array, x: float, y: float, t: float, k: float, i: int) -> void:
	if k <= 0.0:
		return
	# two thin tongues lick up out of the socket and past the brow, swaying, cooling to violet
	for j: float in [-0.6, 0.7]:
		var h := (1.5 + 3.0 * (0.5 + 0.5 * Px.noise(t * 8.0 + j * 3.1 + i * 7, 4))) * k
		var sw := Px.noise(t * 4.0 + j * 2.0 + i * 3, 8) * 1.2
		var d := 1.0
		while d <= h:
			var u := d / h
			p.dot(x + j + sw * u * u, y - d, C[7] if u < 0.3 else (C[6] if u < 0.6 else (C[5] if u < 0.85 else C[4])), 1.0 if u < 0.75 else (1.0 - u) * 4.0)
			d += 0.5
	# the pupil: a hard white point in the dark
	p.px(x, y, WHITE)
	p.px(x - 1.0, y, C[6])
	p.glow(x, y, 8.0, C[5], 0.5 * k)


var C: Array
var K: Array
var R: Px.Rng
var A: Variant
var ps: Px.Particles
var puffs: Lib.Puffs
var dust: Lib.Puffs
var bits: Px.Bits
var lights: Array = []
var t := 0.0
var stamped := false
var broke := false
var acc := 0.0
var head := 0.0


func create(o: Dictionary) -> void:
	C = Px.fit(o.palette, 8)
	K = Px.fit(o.bone, 5)
	R = Px.Rng.new(o.seed)
	A = o.get("actor")
	var floor_ := func(): return 0.0
	ps = Px.Particles.new({"rng": R, "ground": floor_, "sparks": [WHITE, C[7], C[6], C[5]], "haze": C[4]})
	puffs = Lib.Puffs.new({"rng": R, "flame": [WHITE, C[7], C[6], C[5], C[4], C[3], C[2], C[1], C[0]], "soot": [Px.mix(C[3], C[2], 0.5), Px.mix(C[1], C[0], 0.3)], "cap": Px.mix(C[4], C[2], 0.5), "rim": [C[6], C[5], C[4]], "floor": floor_})
	dust = Lib.Puffs.new({"rng": R, "flame": [WHITE, WHITE, WHITE, WHITE, WHITE, WHITE, WHITE, WHITE, WHITE], "soot": [Px.mix(K[2], K[1], 0.4), Px.mix(K[1], K[0], 0.5)], "cap": K[3], "rim": [K[4], K[3], K[2]], "floor": floor_})
	bits = Px.Bits.new({"ground": floor_})
	lights = []
	t = 0.0
	stamped = false
	broke = false
	acc = 0.0
	head = A.y if A else -38.0


func light(x: float, y: float, r: float, c: Variant, k: float, life: float) -> void:
	lights.append({"x": x, "y": y, "r": r, "c": c, "k": k, "life": life, "max": life})


func update(dt: float) -> void:
	t += dt
	# wisps and motes gather over the head, spiralling in
	if t < STAMP - 0.05:
		var k := t / STAMP
		acc += dt * (40.0 + 60.0 * k)
		while acc > 1.0:
			var a := R.range(0.0, TAU)
			var D := R.range(22.0, 44.0)
			ps.spawn(P.MOTE, cos(a) * D, SY + sin(a) * D * 0.8, -sin(a) * 60.0, cos(a) * 60.0, 0.8, R.pick([WHITE, C[7], C[6], C[5]]), R.range(0.6, 1.0))
			acc -= 1.0
		if R.chance(dt * 14.0):
			var a := R.range(0.0, TAU)
			var D := R.range(20.0, 34.0)
			puffs.spawn(PK.SOOT, cos(a) * D, SY + sin(a) * D * 0.7, -sin(a) * 40.0, cos(a) * 30.0, R.range(0.5, 0.7), R.range(3.0, 5.5))
		Lib.attract(ps.list, 0.0, SY, 9e5 * (0.4 + k), 70.0, 0.6, 2.5, dt, func(q): return 1.0 if q.k == P.MOTE else 0.0, 300.0)
		Lib.attract(puffs.list, 0.0, SY, 5e5 * (0.4 + k), 60.0, 0.7, 3.5, dt, func(): return 1.0, 120.0)
	if t >= STAMP and not stamped:
		stamped = true
		ps.list.clear()
		puffs.list.clear()
		light(0.0, SY, 64.0, C[5], 1.0, 0.35)
		light(0.0, SY, 30.0, WHITE, 1.0, 0.1)
		light(0.0, head + 12.0, 40.0, C[4], 0.6, 0.5)
		for i in 22:
			var a := R.range(0.0, TAU)
			var sp := R.range(80.0, 160.0)
			ps.spawn(P.SPARK, cos(a) * 6.0, SY + sin(a) * 6.0, cos(a) * sp, sin(a) * sp - 30.0, R.range(0.2, 0.5))
		for i in 6:
			var a := R.range(0.0, TAU)
			var sp := R.range(20.0, 45.0)
			puffs.spawn(PK.SOOT, cos(a) * 8.0, SY + sin(a) * 6.0, cos(a) * sp, sin(a) * sp * 0.6 - 10.0, R.range(0.6, 0.9), R.range(2.5, 4.5))
	# it burns: embers and thin smoke off the eyes, a violet haze round it, the curse dripping onto the head
	if stamped and not broke:
		for e: Array in EYES:
			var ex: float = e[0]
			var ey: float = e[1]
			if R.chance(dt * 9.0):
				ps.spawn(P.EMBER, ex, SY + ey - 3.0, R.range(-10.0, 10.0), -R.range(20.0, 45.0), R.range(0.5, 0.9), C[6])
			if R.chance(dt * 7.0):
				puffs.spawn(PK.SOOT, ex + R.range(-1.0, 1.0), SY + ey - 3.0, R.range(-5.0, 5.0), -R.range(14.0, 26.0), R.range(0.5, 0.8), R.range(1.4, 2.4))
		if R.chance(dt * 8.0):
			ps.spawn(P.VAPOUR, R.range(-7.0, 7.0), SY + R.range(-6.0, 6.0), R.range(-12.0, 12.0), R.range(-12.0, 4.0), R.range(0.5, 0.8), C[3] if R.chance(0.5) else C[4], R.range(5.0, 8.0))
		# the curse runs down from the skull into the head
		if R.chance(dt * 12.0):
			ps.spawn(P.MOTE, R.range(-4.0, 4.0), SY + 9.0, R.range(-6.0, 6.0), R.range(40.0, 70.0), R.range(0.25, 0.4), C[6] if R.chance(0.5) else C[5], 0.8)
		if R.chance(dt * 10.0):
			puffs.spawn(PK.SOOT, R.range(-3.5, 3.5), SY + 9.0, R.range(-3.0, 3.0), R.range(14.0, 26.0), R.range(0.45, 0.7), R.range(1.2, 2.2))
		if t > STAMP + 0.3 and R.chance(dt * 5.0):
			ps.spawn(P.STAR, R.range(-1.0, 1.0) * (A.w / 2.0 if A else 10.0), head + R.range(4.0, A.h - 4.0 if A else 30.0), 0.0, -6.0, R.range(0.3, 0.5), C[6], R.range(1.0, 2.0))
	if t >= BREAK and not broke:
		broke = true
		# the skull breaks: chunks of bone tumble and bounce, grit rains, dust and the last of the fire rise
		for i in 24:
			var x := 0.0
			var y := 0.0
			while true:
				x = R.range(-8.5, 8.5)
				y = R.range(-9.0, 9.0)
				if inSkull(floori(x + SW / 2.0), floori(y + SH / 2.0)):
					break
			bits.add({"kind": B.CHUNK, "x": x, "y": SY + y, "vx": x * R.range(2.5, 6.0) + R.range(-12.0, 12.0), "vy": R.range(-70.0, 10.0), "g": 0.85, "drag": 0.4, "bounce": 0.35, "life": R.range(0.8, 1.2), "a": R.range(0.0, TAU), "va": R.range(-14.0, 14.0), "s": R.range(1.0, 2.4), "ramp": [K[0], K[1], K[2], K[3], K[4]]})
		for i in 26:
			ps.spawn(P.GRIT, R.range(-7.0, 7.0), SY + R.range(-8.0, 8.0), R.range(-32.0, 32.0), R.range(-60.0, 20.0), R.range(0.8, 1.3), R.pick([K[2], K[3], K[3], K[4]]), 2.0 if R.chance(0.3) else 1.0)
		for i in 7:
			dust.spawn(PK.SOOT, R.range(-7.0, 7.0), SY + R.range(-8.0, 6.0), R.range(-25.0, 25.0), R.range(-20.0, 5.0), R.range(0.5, 0.8), R.range(2.0, 4.0), R.range(0.0, 0.1))
		for e: Array in EYES:
			var ex: float = e[0]
			var ey: float = e[1]
			puffs.spawn(PK.FLAME, ex, SY + ey, Px.sign(ex) * 6.0, -30.0, 0.5, 2.6, 0.0, false)
		light(0.0, SY, 40.0, C[5], 0.5, 0.25)
	for i in range(lights.size() - 1, -1, -1):
		lights[i].life -= dt
		if lights[i].life <= 0.0:
			lights.remove_at(i)
	# chunks that land kick up a little dust
	bits.update(dt)
	for b: Dictionary in bits.list:
		if b.rest and not b.get("dusted", false):
			b.dusted = true
			dust.spawn(PK.SOOT, b.x, -1.5, R.range(-12.0, 12.0), -R.range(4.0, 10.0), R.range(0.35, 0.6), R.range(1.5, 2.5))
	ps.update(dt)
	puffs.update(dt)
	dust.update(dt)


func drawBack(p: Px.Painter) -> void:
	puffs.draw(p, PK.SOOT, {"x": 0.0, "y": SY, "k": 0.8 if (stamped and not broke) else 0.3, "reach": 50.0})
	dust.draw(p, PK.SOOT)
	ps.draw(p, "back")


func draw(p: Px.Painter) -> void:
	# the curse floods down the body from the head, a bright front ahead of it, then ebbs
	var flood := Px.smooth(STAMP + 0.04, STAMP + 0.42, t)
	var ebb := 1.0 - Px.smooth(BREAK + 0.15, BREAK + 0.75, t)
	if A and flood > 0.0 and ebb > 0.0:
		var k := ebb
		var pulse := 0.85 + 0.15 * sin(t * 9.0)
		var aw: int = A.w
		var ah: int = A.h
		var pix: PackedInt32Array = A.pixels
		for my in ah:
			var u := my / float(ah)
			if u > flood + 0.06:
				break
			var edge := flood < 1.0 and absf(u - flood) < 0.05
			var band := flood >= 1.0 and absf(u - fmod((t - STAMP) * 1.3, 1.4) + 0.2) < 0.06
			for mx in aw:
				var c0 := pix[my * aw + mx]
				if not c0:
					continue
				var l := Px.luma(c0)
				var cc: int = C[6] if l > 0.72 else (C[5] if l > 0.5 else (C[4] if l > 0.33 else (C[3] if l > 0.18 else C[2])))
				p.blend(A.x + mx, A.y + my, C[7] if edge else (C[6] if band else cc), 0.85 if edge else (0.7 * k if band else 0.6 * k * pulse))
		# a crawling violet edge round the cursed body
		p.outline(A.mask, A.x, A.y, func(mx, my): return C[6] if sin(my * 0.7 - t * 14.0 + mx * 0.3) > 0.2 else C[4], func(mx, my): return k if my / float(ah) <= flood else 0.0)
		p.glow(0.0, A.y + A.h * 0.45, 30.0, C[4], 0.3 * k * pulse)
	# the gathering: a dim swirl of light where the skull will be
	if t < STAMP:
		var q := t / STAMP
		p.glow(0.0, SY, 14.0 + 16.0 * q, C[5], 0.2 + 0.5 * q)
		if q > 0.15:
			Lib.ringFast(p, 0.0, SY, 4.0 + 30.0 * (1.0 - Px.Ease.inQuad(q)), 1.0, C[5] if q > 0.7 else (C[4] if q > 0.4 else C[3]))
	# the skull: it slams down from big and pale, squashes, bobs while it burns, shakes as it cracks
	if t >= STAMP and t < BREAK:
		var u := (t - STAMP) / 0.1
		var s := 1.7 - 0.7 * Px.Ease.inQuad(u) if u < 1.0 else 1.0
		var land := t - STAMP - 0.1
		var sq := 1.0 - 0.16 * exp(-land * 18.0) * cos(land * 40.0) if land > 0.0 else 1.0
		var shake := (t - CRACK) * 4.0 if t > CRACK else 0.0
		var ox := Px.round(sin(t * 61.0) * shake)
		var oy := Px.round(sin(t * 3.4) * 1.2) if land > 0.0 else 0.0
		skull(p, C, K, s, sq, ox, oy, t < STAMP + 0.067, Px.smooth(CRACK, BREAK, t))
		var burn := Px.smooth(STAMP + 0.1, STAMP + 0.25, t)
		if u >= 1.0:
			for i in EYES.size():
				var ex: float = EYES[i][0]
				var ey: float = EYES[i][1]
				eyeFire(p, C, ox + ex, SY + oy + ey, t, burn * (1.0 + 0.4 * Px.smooth(CRACK, BREAK, t)), i)
		if u < 1.2:
			Px.sparkle(p, 0.0, SY, 14.0 * (1.0 - u / 1.2), C[7], C[5], 0.6)
		p.glow(0.0, SY, 26.0, C[4], 0.25)
	# the stamp's shock ring
	var ru := (t - STAMP - 0.08) / 0.3
	if ru > 0.0 and ru < 1.0:
		Lib.ringFast(p, 0.0, SY + 2.0, 10.0 + 26.0 * Px.Ease.outCubic(ru), maxf(1.0, 2.5 * (1.0 - ru)), func(v): return WHITE if v > 0.5 else C[6], 1.2 - ru)
	bits.draw(p)
	puffs.draw(p, PK.FLAME)
	ps.draw(p, "front")
	for l: Dictionary in lights:
		var q: float = l.life / l.max
		p.glow(l.x, l.y, l.r * (0.6 + 0.4 * q), l.c, l.k * q * q)
	# bone keeps its own colours under the glow (all but the stamp's white frame)
	if t >= STAMP + 0.067 and t < BREAK:
		Lib.unlight(p, -10.0, SY - 10.0, 10.0, SY + 10.0, func(x, y):
			var u := floori(x + SW / 2.0)
			var v := floori(y - SY + SH / 2.0)
			return inSkull(u, v) and SKULL[v][u] != "e", 0.2)
