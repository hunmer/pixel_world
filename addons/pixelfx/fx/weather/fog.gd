# The banded fog (a baked tiling noise, warped, cut into a few translucent tones with Bayer edges, a lit crest
# wherever a band's top meets thinner fog) is adapted from Sprite Fusion's open-source fog
# (https://www.spritefusion.com/pixel-art-vfx/fog), MIT License, Copyright (c) 2026 Hugo Duprez.
# port-of: src/fx/weather/fog.js@68785cbc590bd950fd124ba18be6f85f62a4cf3c
extends RefCounted

const Px := preload("../../core/px.gd")
const Lib := preload("_lib.gd")

static var meta := {
	"name": "Fog",
	"desc": "Slow banks of moonlit fog at three depths drift past each other, crests catching the light, while thin streaks of mist slide by in front.",
	"tags": ["weather", "fog", "mist", "haze", "night", "ambient", "loop"],
	"size": [320, 180],
	"origin": [160, 170],
	"duration": 12.0,
	"loop": true,
	"fps": 30,
	"bg": "sky",
	"options": {
		"palette": ["#14121e", "#24213a", "#363250", "#4f4a6c", "#6d688b", "#918cab", "#bdb8d4", "#ece8f6"],
		"seed": 5,
	},
}

const D := 12.0
const W := 320
const T := [0.3, 0.5, 0.7]
const BW := 0.06
# far to near: where each bank's top thins out (top..base), how far down it reaches, noise scale (the tile it
# scrolls each loop is 256 / sx px wide), tiles a loop, how opaque, tones [thin, body, dense], crest tone
const BANKS := [
	{"top": -84.0, "base": -40.0, "bot": -20.0, "sx": 1.6, "sy": 2.2, "lap": 1.0, "alpha": 0.24, "tone": [2, 3, 4], "crest": 5, "warp": 16.0, "crestFrom": 3},
	{"top": -62.0, "base": -24.0, "bot": -2.0, "sx": 1.0667, "sy": 2.5, "lap": 1.0, "alpha": 0.3, "tone": [2, 3, 4], "crest": 5, "warp": 22.0, "crestFrom": 2},
	{"top": -42.0, "base": -8.0, "bot": 10.0, "sx": 0.8, "sy": 2.8, "lap": 1.0, "alpha": 0.36, "tone": [2, 3, 5], "crest": 6, "warp": 28.0, "crestFrom": 1},
]
static var BR := _f32(W)
static var P1 := BANKS.map(func(_b): return _f32(W))
static var P2 := BANKS.map(func(_b): return _f32(W))
static var WARP := _f32(W)


static func _f32(n: int) -> PackedFloat32Array:
	var a := PackedFloat32Array()
	a.resize(n)
	return a


static func drawBack(p: Px.Painter, t: float, o: Dictionary) -> void:
	var S: float = o.seed
	var C := Px.fit(o.palette, 8)
	bank(p, t, S, C, 0)
	bank(p, t, S, C, 1)


static func draw(p: Px.Painter, t: float, o: Dictionary) -> void:
	var S: float = o.seed
	var C := Px.fit(o.palette, 8)
	bank(p, t, S, C, 2)
	streaks(p, t, S, C, 1)


static func bank(p: Px.Painter, t: float, S: float, C: Array, n: int) -> void:
	var B: Dictionary = BANKS[n]
	var F := Lib.field(S * 7 + n, 256, 128)
	var G := Lib.field(S * 7 + 11, 256, 128, [4, 8, 16])
	var drift: float = (256 * B.lap * t) / D
	var boil := (128 * t) / D
	var prev1: PackedFloat32Array = P1[n]
	var prev2: PackedFloat32Array = P2[n]
	var tones: Array = B.tone.map(func(i): return C[i])
	var crest := Px.mix(C[B.crest], Px.WHITE, 0.12 + 0.08 * n)
	prev1.fill(0)
	prev2.fill(0)
	# the fog breathes: its top rises and falls a little along its length
	for i in W:
		BR[i] = 2 * sin((TAU * t) / D + (i - 160) * 0.006 + n * 1.7)
	var top: float = B.top
	var base: float = B.base
	var bot: float = B.bot
	var bsx: float = B.sx
	var bsy: float = B.sy
	var warp: float = B.warp
	var alpha: float = B.alpha
	var crestFrom: int = B.crestFrom
	var br := BR
	var wp := WARP
	Lib.rows(p, meta, top - 2, bot, func(y: float, R: Lib.Row) -> void:
		var Rc := R.c
		var Ra := R.a
		var Rb := R.b
		var Rl := R.l
		var Rk := R.k
		var prof := Px.smooth(top, base, y) * (1 - Px.smooth(bot - (14 if bot < 10 else 4), bot + 1, y))
		var i := 0
		while i < W:
			var v := Lib.sample(G, i * 0.35 + n * 70, y * 0.5 + boil) - 0.5
			wp[i + 1] = v
			wp[i] = v
			i += 2
		for j in W:
			var x := j - 160 + 0.5
			var w := wp[j]
			# the noise is pushed hard and clamped so it, not the height, shapes the fog: blobs, not stripes
			var nn := Px.clamp((Lib.sample(F, x * bsx + drift + w * warp, (y + br[j]) * bsy + w * 8) - 0.5) * 2.6 + 0.5) - 0.5
			var f := 0.0 if prof <= 0.01 else (prof * 0.72 + nn * 0.95) * (0.6 + 0.5 * prof)
			var above := prev2[j]
			prev2[j] = prev1[j]
			prev1[j] = f
			if f <= T[0]:
				continue
			var th := Lib.bayer(j, y) * BW
			var band := 2 if f > T[2] + th else (1 if f > T[1] + th else 0)
			var solid := 2 if f > T[2] else (1 if f > T[1] else 0)
			# a lit crest, one pixel thick, where this band's top meets thinner fog
			if solid >= crestFrom and above < T[solid]:
				Rc[j] = crest
				Ra[j] = alpha * 0.95
				Rl[j] = C[6]
				Rk[j] = 0.07
			else:
				# dense fog scatters the most moonlight: it's the brightest part, with a little glow
				Rc[j] = tones[band]
				Ra[j] = alpha * (0.55 + 0.25 * band)
				if band == 2:
					Rl[j] = C[5]
					Rk[j] = 0.03 + 0.02 * n
			Rb[j] = 1)


# thin streaks of mist sliding by faster than the banks, a few behind the near bank and a few in front
static func streaks(p: Px.Painter, t: float, S: float, C: Array, front: int) -> void:
	# one tile a loop: the back streaks slide at 43 px/s, the front ones at 53
	var F := Lib.field(S * 7 + 20 + front, 256, 128)
	var drift := (256 * t) / D
	var sx := 0.4 if front else 0.5
	var y0 := -40.0 if front else -96.0
	var y1 := 6.0 if front else -30.0
	Lib.rows(p, meta, y0, y1, func(y: float, R: Lib.Row) -> void:
		var Rc := R.c
		var Ra := R.a
		var Rb := R.b
		var Rl := R.l
		var Rk := R.k
		var env := Px.smooth(y0, y0 + 10, y) * (1 - Px.smooth(y1 - 10, y1, y))
		for i in W:
			var x := i - 160 + 0.5
			var s := (Lib.sample(F, x * sx + drift, y * 6.5 + 30) - 0.64) * 3 * env
			if s <= 0.05:
				continue
			Rc[i] = C[5] if s > 0.35 else C[4]
			Ra[i] = minf(0.4, s)
			Rb[i] = 1
			Rl[i] = C[5]
			Rk[i] = s * 0.05)
