# The glints (a cross of rays with a white heart and soft light, little twinkling stars around it) are adapted from
# Sprite Fusion's open-source sparkle (https://www.spritefusion.com/pixel-art-vfx/sparkle), MIT License,
# Copyright (c) 2026 Hugo Duprez.
# port-of: src/fx/weather/shooting-stars.js@292d44454a83d069beb930edabd68c9f0ac0ef82
extends RefCounted

const Px := preload("../../core/px.gd")
const Lib := preload("_lib.gd")

static var meta := {
	"name": "Shooting stars",
	"desc": "Meteors burn across a starry sky, white heads trailing gold and rose; the big ones flare and break up, and each leaves a glowing train that twists and fades.",
	"tags": ["weather", "meteor", "shooting star", "night", "sky", "stars", "ambient", "loop"],
	"size": [320, 180],
	"origin": [160, 180],
	"duration": 10.0,
	"loop": true,
	"fps": 30,
	"bg": "sky",
	"options": {
		"palette": ["#3a1e5a", "#7a3a8a", "#e0607a", "#ffa86a", "#ffe6a8", "#ffffff"],
		"sky": ["#141428", "#2a2a4a", "#4c4c7c", "#8e8ec4", "#dcdcff"],
		"seed": 4,
	},
}

const D := 10.0
# the meteors: when, where they start, which way, how fast, how long they burn, how big; the last flares
const METEORS := [
	{"t0": 0.5, "x": 60.0, "y": -170.0, "a": 2.45, "v": 260.0, "life": 0.55, "s": 0.6},
	{"t0": 1.9, "x": -40.0, "y": -176.0, "a": 2.2, "v": 220.0, "life": 0.7, "s": 0.8},
	{"t0": 3.4, "x": 150.0, "y": -150.0, "a": 2.62, "v": 300.0, "life": 0.45, "s": 0.5},
	{"t0": 4.6, "x": 130.0, "y": -178.0, "a": 2.35, "v": 240.0, "life": 1.05, "s": 1.4, "flare": true},
	{"t0": 6.7, "x": -90.0, "y": -168.0, "a": 2.05, "v": 200.0, "life": 0.6, "s": 0.7},
	{"t0": 7.9, "x": 20.0, "y": -160.0, "a": 2.5, "v": 280.0, "life": 0.5, "s": 0.6},
	{"t0": 9.2, "x": -10.0, "y": -176.0, "a": 2.28, "v": 230.0, "life": 0.8, "s": 1.0, "flare": true},
]
const TRAIN := 1.6


static func draw(p: Px.Painter, t: float, o: Dictionary) -> void:
	var q := Lib.clip(p, meta)
	var _B := Lib.box(meta)
	var S: float = o.seed
	var C := Px.fit(o.palette, 6)
	var K := Px.fit(o.sky, 5)
	sky(p, q, t, S, K)
	for i in METEORS.size():
		var m: Dictionary = METEORS[i]
		meteor(q, Px.wrap(t - m.t0, D), m, i, S, C)


# the starfield: a faint milky band across the sky, dim specks, steady stars, a few that twinkle with a glint
static func sky(p: Px.Painter, q: Px.Painter, t: float, S: float, K: Array) -> void:
	var K2: int = K[2]
	Lib.rows(p, meta, -180, -1, func(y: float, R: Lib.Row) -> void:
		var Rc := R.c
		var Ra := R.a
		var Rl := R.l
		var Rk := R.k
		for i in 320:
			var x := i - 160 + 0.5
			var d := absf((y + 110) - (x * -0.32)) / 36
			if d >= 1:
				continue
			var k := (1 - d) * (1 - d)
			Rl[i] = K2
			Rk[i] = 0.1 * k
			if Px.rand(i, floorf(y), S, 5) < 0.05 * k:
				Rc[i] = K2
				Ra[i] = 0.7)
	for i in 130:
		var x := -160 + Px.rand(S, i, 1) * 320
		var y := -180 + Px.rand(S, i, 2) * 178
		var r := Px.rand(S, i, 3)
		var c := 1 + floorf(Px.rand(S, i, 4) * 4)
		var tw := 0.5 + 0.5 * sin((TAU * c * t) / D + Px.rand(S, i, 5) * TAU)
		if r < 0.6:
			q.dot(x, y, K[3], 0.35 + 0.5 * tw)
		elif r < 0.94:
			q.px(x, y, K[4] if r < 0.8 else Px.WHITE)
			q.glow(x + 0.5, y + 0.5, 3, K[3], 0.22 * tw)
		else:
			Px.sparkle(q, x, y, 1 + Px.round(tw * 2), K[4], K[3], 0.3 * tw)


# one meteor, age seconds after it lights: a head that brightens and burns out, a trail cooling down the ramp
# behind it, a flare and fragments for the big ones, and the train it leaves glowing and twisting as it fades
static func meteor(q: Px.Painter, age: float, m: Dictionary, i: int, S: float, C: Array) -> void:
	var flare: bool = m.get("flare", false)
	var mx: float = m.x
	var my: float = m.y
	var mv: float = m.v
	var life: float = m.life
	var ms: float = m.s
	var ca := cos(m.a)
	var sa := sin(m.a)
	var end := life + (0.5 if flare else 0.0) + TRAIN
	if age > end:
		return
	var pos := func(tt: float) -> Array: return [mx + ca * mv * tt, my + sa * mv * tt]
	var burn := minf(age, life)
	var hxy: Array = pos.call(burn)
	var hx: float = hxy[0]
	var hy: float = hxy[1]
	# the train: the whole path it has burned, lingering, widening, drifting and twisting
	var trainK := 1.0 if age < life else 1 - (age - life) / (TRAIN + (0.5 if flare else 0.0))
	if trainK > 0:
		var len_ := mv * burn
		var nx := -sa
		var ny := ca
		var d := 0
		while d < len_:
			var passed := age - d / mv
			if passed < 0.08:
				d += 1
				continue
			var g := trainK * minf(1, (passed - 0.08) * 4) * (0.35 + 0.65 * sin((PI * d) / len_)) * ms
			var tw := sin(d * 0.09 + passed * 1.7) * minf(4, passed * 3)
			var x := mx + ca * d + nx * tw + passed * 4
			var y := my + sa * d + ny * tw
			q.dot(x, y, C[2] if passed < 0.6 else C[1], g * 0.75)
			if d % 6 == 0:
				q.glow(x, y, 6 + passed * 4, C[1], 0.12 * g)
			d += 1
	if age > life + (0.5 if flare else 0.0):
		return
	# the head brightens fast, holds, and burns out; the big ones flare as they go
	var u := age / life
	var k := minf(1, u * 6) * (1 - (u - 0.75) / 0.25 if u > 0.75 else 1.0) if age < life else 0.0
	if k > 0:
		var L := (24 + 40 * ms) * minf(1, u * 3)
		var rev := C.slice(1)
		rev.reverse()
		var d := 0.0
		while d <= L:
			var v := d / L
			var x := hx - ca * d
			var y := hy - sa * d
			q.dot(x, y, Px.WHITE if v < 0.08 else Px.at(rev, v * 0.95), k * (1.0 if v < 0.6 else (1 - v) / 0.4))
			if ms > 0.9 and v < 0.4:
				q.dot(x - sa * 0.9, y + ca * 0.9, C[4] if v < 0.15 else C[3], k * (1 - v / 0.4))
			d += 0.5
		q.px(hx, hy, Px.WHITE)
		if ms > 0.9:
			q.px(hx + 1, hy, Px.WHITE)
			q.px(hx, hy + 1, C[4])
		q.glow(hx, hy, 8 + 10 * ms, C[4], 0.45 * k)
		q.glow(hx - ca * L * 0.3, hy - sa * L * 0.3, 10 + 8 * ms, C[3], 0.2 * k)
	if not flare or age < life * 0.82:
		return
	# the flare: a burst of light and rays, fragments carrying on and fading
	var f := (age - life * 0.82) / (life * 0.18 + 0.5)
	var fxy: Array = pos.call(life * 0.86)
	var fx: float = fxy[0]
	var fy: float = fxy[1]
	if f < 0.35:
		Px.sparkle(q, fx, fy, 9 * sin((PI * f) / 0.35) + 2, C[4], C[3], 0.6)
		q.glow(fx, fy, 40, C[3], 0.5 * (1 - f / 0.35))
	# little stars scattered round the burst, each twinkling once and gone
	for j in 7:
		var ang := Px.rand(S, i, j, 5) * TAU
		var r := 5 + Px.rand(S, i, j, 6) * 16
		var d0 := Px.rand(S, i, j, 7) * 0.3
		var g := (f - d0) / 0.45
		if g <= 0 or g >= 1:
			continue
		var sx := fx + cos(ang) * r * (0.6 + g * 0.5)
		var sy := fy + sin(ang) * r * (0.6 + g * 0.5) - g * 3
		var arm := Px.round(2.5 * sin(PI * g))
		if arm >= 1:
			Px.sparkle(q, sx, sy, arm, C[4] if j % 3 else Px.WHITE, C[3], 0.3 * (1 - g))
		else:
			q.px(sx, sy, C[4])
	for j in 4:
		var da := (Px.rand(S, i, j, 1) - 0.5) * 0.5
		var sp := mv * (0.5 + Px.rand(S, i, j, 2) * 0.4)
		var tt := f * (life * 0.18 + 0.5)
		var g := 1 - f
		var x := fx + cos(m.a + da) * sp * tt
		var y := fy + sin(m.a + da) * sp * tt
		if g <= 0:
			continue
		q.line(x - cos(m.a + da) * 5 * g, y - sin(m.a + da) * 5 * g, x, y, C[3], g)
		q.px(x, y, Px.WHITE if g > 0.5 else C[4])
		q.glow(x, y, 5, C[3], 0.35 * g)
