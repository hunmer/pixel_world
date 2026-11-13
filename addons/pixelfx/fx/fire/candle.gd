# The layered flame tongue is adapted from Sprite Fusion's open-source fire
# (https://www.spritefusion.com/pixel-art-vfx/fire), MIT License, Copyright (c) 2026 Hugo Duprez.
# port-of: src/fx/fire/candle.js@a2b32eefcb47b8bb88edd5e6d02900d9693a5724
extends RefCounted

const Px := preload("../../core/px.gd")
const Lib := preload("_lib.gd")
const WHITE := Px.WHITE

static var meta := {
	"name": "Candle",
	"desc": "A wax candle in a brass dish: a calm flame with a blue root that sways and stretches, a halo of light, motes drifting in it, a bead of wax running down a drip.",
	"tags": ["fire", "candle", "prop", "light", "calm", "ambient", "loop"],
	"size": [56, 76],
	"origin": [28, 64],
	"duration": 4,
	"loop": true,
	"fps": 30,
	"bg": "ground",
	"options": {
		"palette": ["#4a1712", "#8a1f17", "#c9281f", "#f2561d", "#ff8a2a", "#ffc23d", "#ffe26b", "#fff3a6", "#ffffff"],
		"root": ["#1b2a8a", "#3a62e0", "#7fb4ff"],
		"wax": ["#2e201e", "#5e4436", "#8e6e58", "#b8957a", "#d8b896", "#f0dcc0"],
		"brass": ["#2a1a10", "#6a4a1e", "#b4862e", "#e8c060", "#fff0b0"],
		"seed": 2,
	},
}

static var D: float = meta.duration
static var NL: Callable = Lib.noiseFor(D)
const TOP := -16.0
const WICK := TOP - 3.0
# a calm flame: an orange rim round gold, yellow, a pale heart and a small white core low down
const CALM := [[1.0, 1.0, 5], [0.8, 0.88, 3], [0.6, 0.72, 2], [0.38, 0.52, 1], [0.18, 0.3, 0]]
# the bead runs down this drip, from the rim to its bulb
const DRIP := {"x": 4.0, "y0": TOP + 2.0, "y1": -7.0}


static func dish(p: Px.Painter, B: Array, H: Array, fl: float) -> void:
	p.ellipse(0.0, 1.0, 10.0, 2.6, func(d, a): return B[0] if d > 0.82 else ((Px.mix(B[3], H[3], 0.3 * fl) if d > 0.6 else B[2]) if sin(a) < -0.2 else (B[1] if d > 0.55 else B[2])))
	p.rect(-8.0, 2.0, 17.0, 1.0, B[1])
	p.rect(-7.0, 3.0, 15.0, 1.0, B[0])


# the candle: a wax pillar with a dark outline, a highlight band on the lit side, a shadow side, a pool of
# melted wax lit by the flame, a long glossy drip down the right ending in a bulb and a short one on the left
static func candle(p: Px.Painter, X: Array, H: Array, fl: float) -> void:
	var L := TOP
	var cols := [X[1], X[4], X[5], X[4], X[4], X[3], X[3], X[2], X[0]]
	for i in 9:
		var x := i - 4.0
		p.rect(x, L + 1.0, 1.0, -L - 2.0, cols[i])
		if i == 2:
			p.rect(x, -8.0, 1.0, 7.0, X[4])
	p.rect(-3.0, -1.0, 7.0, 1.0, X[2])
	p.px(-4.0, -1.0, X[0])
	p.px(4.0, -1.0, X[0])
	# the rim and the pool of melted wax round the wick, lit by the flame
	p.rect(-3.0, L, 7.0, 1.0, Px.mix(X[5], H[2], 0.25 * fl))
	p.px(-4.0, L, X[1])
	p.px(4.0, L, X[1])
	p.rect(-2.0, L + 1.0, 5.0, 1.0, Px.mix(X[5], H[1], 0.5 * fl))
	p.rect(-1.0, L + 1.0, 3.0, 1.0, Px.mix(X[4], H[2], 0.45 * fl))
	# the long drip: a lighter, glossy run down the right that bulges past the side into a bulb
	var y1: float = DRIP.y1
	p.rect(3.0, L + 1.0, 1.0, y1 - L - 1.0, X[4])
	p.rect(4.0, L + 2.0, 1.0, y1 - L - 2.0, X[3])
	p.px(5.0, L + 3.0, X[0])
	p.rect(5.0, L + 4.0, 1.0, y1 - L - 4.0, X[0])
	p.rect(3.0, y1, 2.0, 2.0, X[4])
	p.px(5.0, y1, X[3])
	p.px(5.0, y1 + 1.0, X[2])
	p.px(6.0, y1, X[0])
	p.px(6.0, y1 + 1.0, X[0])
	p.rect(3.0, y1 + 2.0, 3.0, 1.0, X[0])
	p.px(3.0, L + 2.0, X[5])
	# the short drip on the left
	p.rect(-4.0, L + 1.0, 1.0, 4.0, X[4])
	p.px(-5.0, L + 3.0, X[1])
	p.px(-5.0, L + 4.0, X[1])
	p.px(-4.0, L + 5.0, X[3])


static func draw(p: Px.Painter, t: float, o: Dictionary) -> void:
	var F := Px.fit(o.palette, 9)
	var H := Lib.hotFirst(F)
	var RT := Px.fit(o.root, 3)
	var X := Px.fit(o.wax, 6)
	var B := Px.fit(o.brass, 5)
	var S: float = o.seed
	# calm: everything moves slowly, the flame now and then stretches tall
	var N := func(rate: float, seed: Variant = 0, off: float = 0.0) -> float: return NL.call(t, rate * 0.35, seed, off)
	var fl: float = 0.86 + 0.08 * NL.call(t, 2.0, S + 1.0) + 0.06 * NL.call(t, 7.0, S + 2.0)
	var stretch: float = maxf(0.0, NL.call(t, 0.75, S + 3.0) - 0.3) * 0.6
	var h := 12.0 * (1.0 + stretch) * (0.94 + 0.06 * fl)
	var sway: float = NL.call(t, 0.5, S + 4.0) * 1.6 + NL.call(t, 1.5, S + 5.0) * 0.5
	var GLOW := Px.mix(Px.mix(H[3], H[4], 0.5), WHITE, 0.3)
	var cy := WICK - h * 0.4

	# a pool of warm light on the floor and the halo behind the flame
	Lib.floorLight(p, 0.0, 1.0, 26.0, 5.0, GLOW, 0.3 * fl)
	p.glow(sway * 0.3, cy, 38.0 * fl, GLOW, 0.42 * fl)
	p.glowRing(sway * 0.3, cy, 10.0, 4.0, H[2], 0.12 * fl)
	dish(p, B, H, fl)
	candle(p, X, H, fl)
	# the bead of wax: it swells at the rim, runs down the drip and sets into its bulb
	var run := fmod(t, D) / D
	var swell := Px.smooth(0.0, 0.3, run)
	var slide := Px.smooth(0.3, 0.85, run)
	var set_ := Px.smooth(0.85, 1.0, run)
	if set_ < 1.0 and swell > 0.15:
		var by := Px.round(DRIP.y0 + (DRIP.y1 - DRIP.y0) * slide)
		p.px(DRIP.x, by, Px.mix(X[5], H[1], 0.4 * fl))
		if swell > 0.6 and set_ < 0.5:
			p.px(DRIP.x + 1.0, by, X[4])
			p.px(DRIP.x + 1.0, by + 1.0, X[2])
	# the wick, glowing at its tip
	p.line(0.0, TOP, 0.0, WICK + 1.0, X[0])
	p.px(0.0, WICK + 1.0, H[4])
	# the flame and its blue root
	Lib.flameTongue(p, 0.0, WICK + 1.0, h, 2.6, sway, N, S * 31.0, H, CALM, 0.25, 0.6)
	for dx in range(-2, 3):
		var a := 1.0 - absi(dx) * 0.2
		p.dot(dx, WICK + 1.0, RT[0] if absi(dx) == 2 else RT[1], a)
		if absi(dx) <= 1:
			p.dot(dx, WICK + 2.0, RT[0], 0.7)
	p.px(0.0, WICK, RT[2])
	# a thread of smoke now and then off the tip
	Lib.looped(t, D, 6, S + 300.0, func(r: Px.Rng) -> Dictionary: return {"vx": r.range(-1.5, 1.5), "vy": -r.range(8.0, 12.0), "life": r.range(1.4, 2.2), "s": r.range(0.8, 1.2)}, func(q: Dictionary, age: float) -> void:
		var xy := Lib.drift(sway, WICK - h, q.vx, q.vy, age, 1.0, -6.0, 1.0, 0.8)
		Lib.smokePuff(p, xy[0] + NL.call(t - age, 0.6, S + 60.0) * (1.0 + age * 2.0), xy[1], 1.0 - age / q.life, q.s, 0, false, 0.6))
	# motes drifting in the candlelight, catching it as they pass close
	Lib.looped(t, D, 10, S + 400.0, func(r: Px.Rng) -> Dictionary: return {"x": r.range(-20.0, 20.0), "y": r.range(-44.0, -8.0), "vx": r.range(-3.0, 3.0), "vy": r.range(-4.0, 2.0), "life": r.range(2.5, 4.0), "ph": r.range(0.0, 6.3)}, func(q: Dictionary, age: float) -> void:
		var x: float = q.x + q.vx * age + sin(age * 1.3 + q.ph) * 2.0
		var y: float = q.y + q.vy * age
		var d := Px.hypot(x, y - cy)
		var k: float = minf(minf(1.0, age * 2.0), (q.life - age) * 2.0) * Px.clamp(1.2 - d / 26.0)
		if k > 0.15:
			p.dot(x, y, H[1] if k > 0.6 else H[3], k)
			p.glow(x, y, 3.0, H[2], 0.2 * k))
	# the hot core of the light
	p.glow(sway * 0.5, WICK - h * 0.3, 10.0, H[1], 0.35 * fl)
