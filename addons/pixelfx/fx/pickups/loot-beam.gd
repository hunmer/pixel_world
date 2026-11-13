# The column recipe (ramp bands out from a white core, drifting strands, dithered edges, light every few rows)
# is adapted from Sprite Fusion's open-source holy light (https://www.spritefusion.com/pixel-art-vfx/holy-light),
# MIT License, Copyright (c) 2026 Hugo Duprez.
# port-of: src/fx/pickups/loot-beam.js@0963f9ff1c7ff97a124d27a0cc8e247e7924c138
extends RefCounted

const Px := preload("../../core/px.gd")
const Lib := preload("_lib.gd")
const WHITE := Px.WHITE

static var meta := {
	"name": "Loot beam",
	"desc": "A dropped sword in a tall pillar of rarity light: a white core thinning to the sky, rings pulsing across the floor, motes streaming up, a glint racing up the shaft.",
	"tags": ["pickup", "loot", "beam", "rarity", "drop", "item", "loop"],
	"size": [96, 176],
	"origin": [48, 162],
	"duration": 2.4,
	"loop": true,
	"fps": 30,
	"bg": "ground",
	"options": {
		"palette": ["#140a24", "#2c1250", "#4b1d86", "#7330c0", "#a050f0", "#c890ff", "#ecd4ff", "#ffffff"],
		"seed": 4,
	},
}

const H := 150.0
const RINGS := [0.08, 0.58]
static var STEEL := Px.ramp(["#151726", "#2c3149", "#4f5775", "#8a93b3", "#d6dcef", "#ffffff"])
static var GOLD := Px.ramp(["#3a2008", "#7a4a10", "#b8801c", "#e8b432", "#ffe27a", "#fff6cc"])
static var LEATHER := Px.ramp(["#1e0f0e", "#3e2016", "#633620"])
static var INK := Px.hex("#0d0b14")
static var L := Lib.Layer.new(40, 24)


# the time since the last ring left the foot, in loop phase, for ring k
static func since(ph: float, k: int) -> float:
	return fmod(fmod(ph - RINGS[k], 1.0) + 1.0, 1.0)


# the sword lying where it fell, 22 px from pommel to point: it rests on its guard and its tip, so the hilt
# lifts off the floor. Built column by column on a stepped axis so its lines stay crisp at 1x.
# The beam rises from the guard; the blade reaches out of the light to the right.
const OX := 4.0
static func axis(x: float) -> float:
	return floorf(-4.0 + (x + 4.0) / 7.0 + 0.5)


static func sword(p: Px.Painter, C: Array, ph: float) -> void:
	var edgeLit := func(x: float) -> int: return C[6] if absf(x + OX - 0.5) < 6.0 else Px.mix(STEEL[4], C[6], 0.45)
	L.begin(-16.0, -12.0)
	# (JS swaps L.set for one that shifts x by OX while the sword is built: the Layer's own setter, moved over)
	var lset := func(x: float, y: float, c: int) -> void: L.setc(x + OX, y, c)
	for xi in range(-11, 11):
		var x := float(xi)
		var a := axis(x)
		if x <= -9.0:
			# the pommel: a stone that holds the beam's colour
			var m := x + 10.0
			if m == 0.0:
				lset.call(x, a - 1.0, C[6])
				lset.call(x, a, WHITE)
				lset.call(x, a + 1.0, C[4])
			else:
				lset.call(x, a, C[5] if m < 0.0 else C[3])
		elif x <= -5.0:
			# the grip, wrapped in leather
			lset.call(x, a, LEATHER[2 if xi % 2 else 1])
			lset.call(x, a + 1.0, LEATHER[1 if xi % 2 else 0])
		elif x <= -3.0:
			# the guard, gold catching the beam on its lit face, a small stone at its heart
			var y := a - 3.0
			while y <= a + 3.0:
				var end := y == a - 3.0 or y == a + 3.0
				lset.call(x, y, (C[6] if x == -4.0 else C[4]) if y == a else ((GOLD[3] if end else Px.mix(GOLD[4], C[6], 0.3)) if x == -4.0 else (GOLD[0] if end else GOLD[1])))
				y += 1.0
		else:
			# the blade: a lit edge on top, steel, a dark spine below, tapering to the point
			# backlit by the beam: a dark body with the beam's colour running along its upper edge
			var tip := x - 8.0
			if tip < 1.0:
				lset.call(x, a - 1.0, edgeLit.call(x))
			if tip < 2.0:
				lset.call(x, a, edgeLit.call(x) if tip == 1.0 else Px.mix(STEEL[3], C[4], 0.2))
			lset.call(x, a + 1.0, STEEL[2] if tip == 2.0 else STEEL[0])
	L.outline(INK).draw(p)
	# a glint slides down the blade's edge once a loop
	var g := (ph - 0.72) / 0.16
	if g > 0.0 and g < 1.0:
		var x := -1.0 + 9.0 * Px.Ease.inOutSine(g)
		Lib.glint(p, x + OX, axis(Px.round(x)) - 1.0, 2.6 * sin(g * PI), WHITE, 0.5)


static func drawBack(p: Px.Painter, t: float, o: Dictionary) -> void:
	var C := Px.fit(o.palette, 8)
	var T: float = meta.duration
	var ph := t / T
	# the floor: a pool of rarity light, a bright spot right under the item
	Lib.pool(p, 0.5, 0.0, 34.0, 5.0, C[4], 0.14)
	# light thrown on the floor in front, kept off the item itself
	p.shade(-30.0, -0.5, 31.0, 6.0, func(x: float, y: float, out) -> void:
		var dx := (x - 0.5) / 30.0
		var dy := y / 6.0
		var d := dx * dx + dy * dy
		if d >= 1.0:
			return
		out.l = C[5]
		out.k = 0.4 * pow(1.0 - sqrt(d), 2))
	for xi in range(-16, 17):
		var x := float(xi)
		var q := absf(x) / 16.5
		var a := 1.35 - q * 1.25
		p.dot(x, 0.0, WHITE if q < 0.3 else (C[6] if q < 0.6 else C[5]), a)
		if q < 0.75:
			p.dot(x, 1.0, C[6] if q < 0.3 else (C[5] if q < 0.55 else C[4]), a * 0.8)
		if q < 0.4:
			p.dot(x, 2.0, C[4], a * 0.5)
	# the far half of each ring, behind the item and the beam
	for k in RINGS.size():
		ring(p, C, since(ph, k) * T, true)
	column(p, C, t, T)


static func draw(p: Px.Painter, t: float, o: Dictionary) -> void:
	var C := Px.fit(o.palette, 8)
	var T: float = meta.duration
	var ph := t / T
	# a soft shadow where it lies, dark in the middle of the lit floor
	Lib.blobShadow(p, OX - 0.5, 12.5, 0.95)
	sword(p, C, ph)
	for k in RINGS.size():
		ring(p, C, since(ph, k) * T, false)
	motes(p, C, t, T, o.seed)


# a ring of light that pulses out across the floor from the item's foot
static func ring(p: Px.Painter, C: Array, a: float, back: bool) -> void:
	var L1 := 1.1
	var k := a / L1
	if k >= 1.0:
		return
	var r := 3.0 + 24.0 * Px.Ease.outCubic(k)
	var th := maxf(1.0, 3.2 * (1.0 - k))
	Px.band(p, 0.5, 0.0, r, 0.2, th, minf(1.0, 1.25 * (1.0 - k)), [C[2], C[4], C[5], C[6]], func(g: float) -> bool: return (sin(g) < 0.0) == back, k < 0.12)
	if not back:
		for s in [-1.0, 1.0]:
			p.glow(0.5 + s * r, -1.0, 8.0, C[5], 0.35 * (1.0 - k))


# the column: bands of the ramp out from a white core, strands drifting through it, pulses climbing it, the
# whole thing thinning and dithering away towards the sky; it swells as each ring leaves its foot
static func column(p: Px.Painter, C: Array, t: float, T: float) -> void:
	var ph := t / T
	var beat := 0.0
	for k in RINGS.size():
		var s := since(ph, k) * T
		beat = maxf(maxf(beat, Px.exp(-s * 7.0) * (1.0 if s < 0.5 else 0.0)), Px.exp(-((T - s) * 30.0)))
	# the glint racing up the shaft once a loop
	var gq := (ph - 0.22) / 0.42
	var gh := 4.0 + (H - 4.0) * Px.Ease.inQuad(gq) if (gq > 0.0 and gq < 1.0) else -100.0
	var shimmer := floorf(ph * 24.0)
	var yi := -1
	while yi >= -H:
		var y := float(yi)
		var h := -y - 0.5
		var u := h / H
		var fade := 1.0 - Px.smooth(0.25, 1.0, u)
		# it narrows with height until only the core is left, and the core breaks into dashes near the top
		var w := (4.2 * (1.0 - 0.45 * u) + 3.2 * Px.exp(-h / 7.0)) * (1.0 + 0.2 * beat)
		# dashes of uneven length, flickering, as the column gives out
		var sg := floorf(h / 3.0 + Px.rand(floorf(h / 9.0), 5) * 2.0)
		var flick := floorf(ph * 12.0)
		if u > 0.66 and Px.rand(sg, flick, 7) > 1.75 - u * 1.65:
			yi -= 1
			continue
		var thread := u > 0.58 and Px.rand(sg, flick, 9) < (u - 0.58) * 3.0
		var climb := 1 if fmod(fmod(h / 30.0 - ph * 3.0, 1.0) + 1.0, 1.0) < 0.1 else 0
		var trail := 1.0 - (gh - h) / 18.0 if (gh - h > 0.0 and gh - h < 18.0) else 0.0
		var X := 0.0 if thread else ceilf(w * 1.6)
		var x := -X
		while x <= X:
			var q := absf(x) / w
			var cw := 0.2 + 0.18 * (1.0 - Px.smooth(0.0, 0.5, u))
			var lvl := 0 if q < cw else (1 if q < 0.47 else (2 if q < 0.72 else (3 if q < 1.0 else 4)))
			for s in 3:
				var sx := (s - 1) * w * 0.55 + sin(h * 0.09 + ph * TAU * (s + 1) + s * 2) * 0.9
				if absf(x - sx) < 0.5:
					lvl = maxi(0, lvl - 1)
			if Px.rand(yi, shimmer, 3) < 0.05 and lvl > 0:
				lvl -= 1
			if q < 0.72:
				lvl = maxi(0, lvl - climb - (1 if trail > 0.3 else 0))
			# the core and inner bands are solid light; only the fringe is dithered, and it goes first
			var a := 1.0 if lvl <= 2 else ((1.55 - q) / 0.75) * fade * 1.2
			if a <= 0.0:
				x += 1.0
				continue
			p.dot(x, y, (C[6] if u > 0.85 else WHITE) if thread else ((C[6] if u > 0.8 else WHITE) if lvl == 0 else C[7 - lvl]), a)
			x += 1.0
		# light all along it: a close glow, and a wide haze that fades with the column
		var near := Px.smooth(8.0, 20.0, h)
		if (yi & 3) == 0:
			p.glow(0.5, y, w * 2.6 + 6.0, C[5], 0.36 * near * (0.3 + 0.7 * fade) * (1.0 + 0.4 * beat))
		if (yi & 15) == 0:
			p.glow(0.5, y, 34.0, C[4], 0.2 * near * (0.25 + 0.75 * fade))
		yi -= 1
	if gh > 0.0:
		Lib.glint(p, 0.0, -gh, 3.5 * (1.0 - gq * 0.5), C[6], 0.6)
		p.glow(0.5, -gh, 14.0, C[5], 0.45)
	# the foot of the beam burns brightest: a small flare where it rises out of the item
	Px.flare(p, 0.5, -5.0, 8.0 + 3.0 * beat + sin(ph * TAU * 4.0) * 0.8, 0.6 + 0.4 * beat, C)
	p.glow(0.5, -16.0, 16.0, C[4], 0.12 + 0.25 * beat)


# motes streaming up round the beam, a few twinkling
static func motes(p: Px.Painter, C: Array, t: float, T: float, seed: Variant) -> void:
	Px.cycle(t, T, 30, seed, func(g: Px.Rng) -> float: return g.range(1.0, 2.2), func(age: float, life: float, r: Px.Rng) -> void:
		var inner := r.chance(0.3)
		var side := r.sign()
		var x0 := r.range(-3.0, 3.0) if inner else side * r.range(4.0, 15.0)
		var vy := r.range(22.0, 52.0) * (1.5 if inner else 1.0)
		var x := x0 + sin(age * r.range(1.5, 3.5) + r.range(0.0, TAU)) * 1.6
		var y := -r.range(1.0, 10.0) - vy * age
		var k := minf(minf(1.0, age / 0.25), (life - age) / 0.5)
		if k <= 0.0 or y < -H:
			return
		if r.chance(0.22):
			var tw := 0.5 + 0.5 * sin(age * r.range(9.0, 14.0) + r.range(0.0, TAU))
			if tw * k > 0.3:
				Lib.glint(p, x, y, 2.0 if tw > 0.75 else 1.0, C[6], 0.4 * k)
			return
		p.dot(x, y, WHITE if inner else C[6], k * 1.5)
		p.dot(x, y + 1.0, C[6] if inner else C[4], k)
		p.dot(x, y + 2.0, C[3], k * 0.6)
		p.glow(x + 0.5, y + 0.5, 3.5, C[5], 0.35 * k))
