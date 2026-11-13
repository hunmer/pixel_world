# The tongue, lick, flame-puff, smoke, ember and spark recipe is adapted from Sprite Fusion's open-source fire
# (https://www.spritefusion.com/pixel-art-vfx/fire), MIT License, Copyright (c) 2026 Hugo Duprez.
# port-of: src/fx/fire/brazier.js@0f9ab2b138afd733a34503395505b37f34ea68a7
extends RefCounted

const Px := preload("../../core/px.gd")
const Lib := preload("_lib.gd")
const WHITE := Px.WHITE

static var meta := {
	"name": "Brazier",
	"desc": "An iron bowl on a tripod heaped with glowing coals and a big roaring fire, sparks and embers streaming up off it, light on the iron and the floor.",
	"tags": ["fire", "brazier", "prop", "light", "sparks", "ambient", "loop"],
	"size": [112, 148],
	"origin": [56, 136],
	"duration": 3,
	"loop": true,
	"fps": 30,
	"bg": "ground",
	"options": {
		"palette": ["#4a1712", "#8a1f17", "#c9281f", "#f2561d", "#ff8a2a", "#ffc23d", "#ffe26b", "#fff3a6", "#ffffff"],
		"iron": ["#0b0910", "#1c1924", "#302c3a", "#4c4658", "#78708a"],
		"seed": 8,
	},
}

static var D: float = meta.duration
static var NL: Callable = Lib.noiseFor(D)
const RIM := -25.0
const RX := 15.0
const RY := 3.0
# the fire: [x, y from the rim, height share, half-width, back row?]
const TONGUES := [
	[-7.0, -1.5, 0.5, 2.0, 1],
	[7.2, -1.5, 0.55, 2.0, 1],
	[-3.0, -2.5, 0.84, 2.2, 1],
	[3.3, -2.5, 0.86, 2.2, 1],
	[-11.5, 0.5, 0.2, 1.5, 0],
	[11.5, 0.5, 0.22, 1.5, 0],
	[-8.3, 0.0, 0.34, 2.0, 0],
	[8.5, 0.0, 0.38, 2.0, 0],
	[-4.7, -0.5, 0.6, 2.8, 0],
	[4.9, -0.5, 0.64, 2.8, 0],
	[0.0, -1.0, 1.0, 3.6, 0],
]


# the tripod: two legs splayed out and one coming at us, curled feet, a ring holding them together
static func stand(p: Px.Painter, I: Array, H: Array, fl: float) -> void:
	var leg := func(x0: float, y0: float, x1: float, y1: float) -> void:
		p.line(x0, y0, x1, y1, I[0])
		p.line(x0 + 1.0, y0, x1 + 1.0, y1, I[2])
		p.line(x0 + 2.0, y0, x1 + 2.0, y1, I[0])
	# the ring: its far half behind the front leg
	p.ellipse(0.0, -9.0, 9.0, 1.8, func(d): return I[2] if d > 0.6 else 0)
	leg.call(-6.0, -17.0, -12.0, -1.0)
	leg.call(4.0, -17.0, 10.0, -1.0)
	p.rect(-14.0, -1.0, 5.0, 1.0, I[2])
	p.rect(-15.0, 0.0, 6.0, 1.0, I[0])
	p.px(-15.0, -1.0, I[3])
	p.rect(9.0, -1.0, 5.0, 1.0, I[2])
	p.rect(9.0, 0.0, 6.0, 1.0, I[0])
	p.px(13.0, -1.0, I[3])
	p.rect(-1.0, -16.0, 3.0, 15.0, I[0])
	p.rect(0.0, -16.0, 1.0, 15.0, Px.mix(I[3], H[4], 0.15 * fl))
	p.rect(-2.0, -1.0, 5.0, 1.0, I[2])
	p.rect(-2.0, 0.0, 5.0, 1.0, I[0])
	p.ellipse(0.0, -9.0, 9.0, 1.8, func(d, a): return ((I[0] if d > 0.85 else I[3]) if sin(a) > 0.0 and d > 0.55 else 0))


# the bowl, front half: a band of rivets under a rim lit by the fire, rounding down to a dark belly
static func bowl(p: Px.Painter, I: Array, H: Array, fl: float) -> void:
	p.shade(-RX - 1.0, RIM - 1.0, RX + 1.0, RIM + 9.0, func(x, y):
		var v: float = (y - RIM) / 9.0
		var hw := RX * sqrt(maxf(0.0, 1.0 - v * v * 0.9)) - ((v - 0.5) * 6.0 if v > 0.5 else 0.0)
		if absf(x) > hw + 0.5 or y < RIM:
			return
		if absf(x) > hw - 0.5 or v > 0.92:
			return I[0]
		if y < RIM + 1.0:
			return Px.mix(I[3], H[4], 0.5 * fl)
		if y < RIM + 2.0:
			return I[2]
		if y < RIM + 3.0:
			return Px.mix(I[4], H[4], 0.25 * fl) if fmod(Px.round(x), 4.0) == 0.0 else I[0]
		return I[2] if x < -RX * 0.45 else (I[1] if x < RX * 0.25 else I[0]))


# coals heaped in the bowl, showing over the rim, breathing in the heat
static func coals(p: Px.Painter, I: Array, H: Array, t: float, S: float) -> void:
	p.shade(-RX, RIM - 6.0, RX, RIM + 1.0, func(x, y, out):
		# a mound: highest in the middle, standing proud of the rim
		var top: float = RIM - 1.0 - 4.0 * maxf(0.0, 1.0 - (x / (RX - 1.0)) ** 2)
		if y < top or y > RIM + 0.5 or absf(x) > RX - 0.5:
			return
		var lump := Px.rand(floorf((x + floorf(y) * 1.5) / 3.0), floorf(y / 2.0), S + 20.0)
		var edge: bool = y < top + 1.0
		# the gaps between lumps stay dark; the lumps breathe, hottest deep in the heap
		if Px.rand(floorf(x), floorf(y), S + 21.0) < 0.16 or (edge and lump < 0.3):
			return I[0]
		var g := (0.5 + 0.5 * sin((t / D) * PI * 4.0 + lump * 40.0)) * (0.7 if edge else 1.0)
		out.k = 0.3 * g
		return H[2] if g > 0.72 else (H[3] if g > 0.5 else (H[4] if g > 0.3 else (H[5] if g > 0.15 else H[6]))))


static func draw(p: Px.Painter, t: float, o: Dictionary) -> void:
	var F := Px.fit(o.palette, 9)
	var H := Lib.hotFirst(F)
	var I := Px.fit(o.iron, 5)
	var S: float = o.seed
	var fl: float = 0.74 + 0.16 * NL.call(t, 7.3, S + 1.0) + 0.1 * NL.call(t, 19.0, S + 2.0)
	var GLOW := Px.mix(Px.mix(H[3], H[4], 0.5), WHITE, 0.25)
	var SPARKS := [H[1], H[2], H[4], H[5]]
	var EMB := [H[1], H[2], H[4], H[6]]
	Lib.floorLight(p, 0.0, 0.5, 40.0, 7.0, GLOW, 0.32 * fl)
	stand(p, I, H, fl)
	# the back of the rim, behind the fire
	p.ellipse(0.0, RIM, RX, RY, func(d, a): return ((I[0] if d > 0.88 else Px.mix(I[3], H[4], 0.3 * fl)) if sin(a) < 0.0 and d > 0.7 else 0))
	Lib.burn(p, t, TONGUES, {
		"H": H, "D": D, "NL": NL, "S": S, "x": 0.0, "y": RIM, "height": 32.0, "lean": 0.1, "spread": 7.0,
		"puffs": 8.0, "licks": 4.0, "smoke": 14.0, "smokeSize": 3.0, "smokeLife": [1.6, 2.4], "embers": 10.0, "glowR": 58.0, "glow": 1.4, "wind": 3.0,
		"mid": func():
			coals(p, I, H, t, S)
			bowl(p, I, H, fl),
	})
	# sparks streaming up in the draught: fast streaks that slow, wander and cool to embers high above
	Lib.looped(t, D, 60, S + 600.0, func(r: Px.Rng) -> Dictionary:
		var side := r.range(-1.0, 1.0)
		return {"x": side * 8.0, "y": RIM - r.range(4.0, 18.0), "vx": side * r.range(10.0, 40.0), "vy": -r.range(70.0, 150.0), "life": r.range(0.7, 1.7), "a": r.range(0.0, 6.3), "w": r.range(1.8, 3.2), "m": r.range(3.0, 8.0), "big": r.chance(0.12)}, func(q: Dictionary, age: float) -> void:
		var e := Lib.drift(q.x, q.y, q.vx, q.vy, age, 0.0, -22.0, 1.9, 1.9)
		var x: float = e[0]
		var y: float = e[1]
		var vx: float = e[2]
		var vy: float = e[3]
		var k: float = 1.0 - age / q.life
		# they bend and wander as the draught slows them
		var wob: float = q.m * (sin(age * q.w + q.a) - sin(q.a)) * minf(1.0, age * 1.5)
		var wv: float = q.m * q.w * cos(age * q.w + q.a) * minf(1.0, age * 1.5)
		if Px.hypot(vx + wv, vy) > 40.0:
			Lib.spark(p, x + wob, y, vx + wv, vy, k, SPARKS)
		else:
			Lib.ember(p, x + wob, y, k, 2.0 if q.big else 1.0, EMB, age * 40.0 + q.a))
