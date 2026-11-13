# The tongue, lick, flame-puff, smoke and ember recipe is adapted from Sprite Fusion's open-source fire
# (https://www.spritefusion.com/pixel-art-vfx/fire), MIT License, Copyright (c) 2026 Hugo Duprez.
# port-of: src/fx/fire/torch.js@e4fc006bf9ce6b4c54f06869fdac765498f5a1d0
extends RefCounted

const Px := preload("../../core/px.gd")
const Lib := preload("_lib.gd")

static var meta := {
	"name": "Torch",
	"desc": "A wall torch on an iron bracket: a licking flame leaping off a pitch-soaked wrap, licks and puffs torn off its tips, smoke, embers, a flickering light on the wall.",
	"tags": ["fire", "torch", "prop", "light", "wall", "dungeon", "loop"],
	"size": [72, 120],
	"origin": [36, 94],
	"duration": 2,
	"loop": true,
	"fps": 30,
	"bg": "dark",
	"options": {
		"palette": ["#4a1712", "#8a1f17", "#c9281f", "#f2561d", "#ff8a2a", "#ffc23d", "#ffe26b", "#fff3a6", "#ffffff"],
		"wood": ["#0e080a", "#24130f", "#3b2216", "#5a3520", "#8a5a34", "#b9884f"],
		"iron": ["#0d0b12", "#1e1b26", "#363242", "#5b5566", "#8a8396"],
		"seed": 4,
	},
}

static var D: float = meta.duration
static var NL: Callable = Lib.noiseFor(D)
const BASE := -16.0
# the flame: [x, y from the wrap's top, height share, half-width, back row?]
const TONGUES := [
	[-1.9, -1.0, 0.74, 2.0, 1],
	[2.1, -1.0, 0.7, 2.0, 1],
	[-3.4, 0.5, 0.42, 1.6, 0],
	[3.6, 0.5, 0.46, 1.6, 0],
	[0.0, 0.0, 1.0, 2.9, 0],
]


# the bracket: a bevelled iron plate on the wall with two rivets, and a ring round the handle
static func plate(p: Px.Painter, I: Array, H: Array, fl: float) -> void:
	p.shade(-5.5, -5.5, 5.5, 11.5, func(x, y):
		if x < -5.0 or x > 5.0 or y < -5.0 or y > 11.0:
			return I[0]
		var rv: bool = absf(x) < 0.6 and (absf(y + 3.5) < 0.6 or absf(y - 9.5) < 0.6)
		if rv:
			return Px.mix(I[4], H[3], 0.35 * fl)
		if y < -4.0 or x < -4.0:
			return Px.mix(I[3], H[4], 0.3 * fl)
		if y > 10.0 or x > 4.0:
			return I[1]
		return I[2] if y < 2.0 else I[1])


static func handle(p: Px.Painter, W: Array) -> void:
	p.shade(-3.0, -12.0, 3.0, 15.0, func(x, y):
		var half: float = 1.3 + Px.clamp((14.0 - y) / 26.0) * 0.9
		if absf(x) > half + 0.5 or y > 14.5:
			return
		if absf(x) > half - 0.5 or y > 13.5:
			return W[0]
		var g := Px.rand(floorf(y / 3.0), Px.round(x), 9)
		return (W[2] if g < 0.3 else W[4]) if x < -0.3 else (W[1] if g < 0.4 else W[2]))


static func ring(p: Px.Painter, I: Array, H: Array, fl: float) -> void:
	p.rect(-3.0, -2.0, 7.0, 4.0, I[0])
	p.rect(-2.0, -1.0, 5.0, 1.0, Px.mix(I[4], H[3], 0.3 * fl))
	p.rect(-2.0, 0.0, 5.0, 1.0, I[2])


# the head: rags bound with cord and soaked in pitch, flaring into a cup at the top, charred where it burns
# with embers breathing in the folds (JS: wrap, which is a GDScript built-in)
static func wrap_(p: Px.Painter, W: Array, I: Array, H: Array, t: float) -> void:
	p.shade(-6.0, BASE - 2.0, 6.0, -9.0, func(x, y, out):
		var v: float = (y - (BASE - 1.5)) / 7.5
		var half := 4.6 - v * 1.9
		if absf(x) > half + 0.5 or y < BASE - 1.5 or y > -9.5:
			return
		if absf(x) > half - 0.5 or y > -10.5:
			return W[0]
		var cord := floori(y - x * 0.6 + 40.0) % 3 == 0
		var h := Px.rand(floorf(x), floorf(y), 31)
		if v < 0.45:
			if h < 0.42:
				var g := 0.5 + 0.5 * sin((t / D) * PI * 4.0 + h * 40.0)
				out.k = 0.3 * g
				return H[2] if g > 0.66 else (H[4] if g > 0.33 else H[5])
			return W[0] if h < 0.75 else W[1]
		if cord:
			return I[2]
		return W[3] if x < -1.0 else (W[2] if x < 1.5 else W[1]))


static func draw(p: Px.Painter, t: float, o: Dictionary) -> void:
	var F := Px.fit(o.palette, 9)
	var H := Lib.hotFirst(F)
	var W := Px.fit(o.wood, 6)
	var I := Px.fit(o.iron, 5)
	var S: float = o.seed
	var fl0: float = 0.74 + 0.16 * NL.call(t, 7.3, S + 1.0) + 0.1 * NL.call(t, 19.0, S + 2.0)
	plate(p, I, H, fl0)
	handle(p, W)
	ring(p, I, H, fl0)
	Lib.burn(p, t, TONGUES, {
		"H": H, "D": D, "NL": NL, "S": S, "x": 0.0, "y": BASE, "height": 20.0, "lean": 0.12, "spread": 4.0,
		"puffs": 10.0, "licks": 5.0, "smoke": 7.0, "smokeSize": 2.3, "smokeLife": [1.3, 2.1], "embers": 7.0, "glowR": 48.0, "glow": 1.25, "wind": 2.0,
		"mid": func(): wrap_(p, W, I, H, t),
	})
